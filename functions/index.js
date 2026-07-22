// Cloud Functions for BLE Attendance App
//
// Deploy this as a Firebase Cloud Function.
//
// Setup:
// 1. cd functions && npm install
// 2. Set SendGrid API key: firebase functions:config:set sendgrid.key="SG.xxx"
// 3. Deploy: firebase deploy --only functions

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const sgMail = require("@sendgrid/mail");
const crypto = require("crypto");

admin.initializeApp();

// Initialize SendGrid
sgMail.setApiKey(functions.config().sendgrid.key);

/**
 * Helper to verify BLE HMAC rotating token with ±30s tolerance.
 * Since BLE payload holds an 8-character fragment, we compare the first 8 characters.
 */
function verifyToken(sessionId, secret, receivedTokenFragment) {
  const currentTimeBucket = Math.floor(Date.now() / 30000);

  for (let offset = -1; offset <= 1; offset++) {
    const bucket = currentTimeBucket + offset;
    const message = `${sessionId}:${bucket}`;
    const hmac = crypto.createHmac("sha256", secret);
    hmac.update(message);
    const expectedToken = hmac.digest("hex").substring(0, 16);
    const expectedFragment = expectedToken.substring(0, 8);

    if (expectedFragment === receivedTokenFragment) {
      return true;
    }
  }
  return false;
}

/**
 * Callable: students retrieve the current BLE rotating token for a session.
 */
exports.getStudentToken = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated.");
  }
  const sessionId = data.sessionId;
  if (!sessionId) {
    throw new functions.https.HttpsError("invalid-argument", "Session ID is required.");
  }

  // Read hmacSecret from secure subcollection details doc
  const secretDoc = await admin.firestore()
    .collection("sessions")
    .doc(sessionId)
    .collection("private")
    .doc("details")
    .get();

  if (!secretDoc.exists) {
    throw new functions.https.HttpsError("not-found", "Session secret not found.");
  }
  const secret = secretDoc.data().hmacSecret;

  // Generate current token
  const currentTimeBucket = Math.floor(Date.now() / 30000);
  const message = `${sessionId}:${currentTimeBucket}`;
  const hmac = crypto.createHmac("sha256", secret);
  hmac.update(message);
  const token = hmac.digest("hex").substring(0, 16);

  return { token };
});

/**
 * Callable: marks student attendance based on BLE token + proximity verification.
 * Enforces security checks including token validity, RSSI, and dwell time.
 */
exports.markAttendance = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated.");
  }

  const { sessionId, studentUid, hmacToken, rssi, scanCount } = data;
  if (!sessionId || !studentUid || !hmacToken || rssi === undefined || scanCount === undefined) {
    throw new functions.https.HttpsError("invalid-argument", "Missing parameters.");
  }

  // Fetch session details
  const sessionDoc = await admin.firestore().collection("sessions").doc(sessionId).get();
  if (!sessionDoc.exists) {
    throw new functions.https.HttpsError("not-found", "Session not found.");
  }
  const session = sessionDoc.data();
  if (session.status !== "active") {
    throw new functions.https.HttpsError("failed-precondition", "Session is not active.");
  }

  // Verify expiration
  const now = admin.firestore.Timestamp.now();
  if (session.endTime.toDate() < now.toDate()) {
    throw new functions.https.HttpsError("failed-precondition", "Session has expired.");
  }

  // Fetch hmacSecret from subcollection
  const secretDoc = await admin.firestore()
    .collection("sessions")
    .doc(sessionId)
    .collection("private")
    .doc("details")
    .get();
  if (!secretDoc.exists) {
    throw new functions.https.HttpsError("not-found", "Session secret not found.");
  }
  const secret = secretDoc.data().hmacSecret;

  // Verify HMAC rotating token
  const isTokenValid = verifyToken(sessionId, secret, hmacToken);
  if (!isTokenValid) {
    throw new functions.https.HttpsError("permission-denied", "Invalid attendance token.");
  }

  // Verify RSSI and dwell-time thresholds
  const rssiThreshold = -75;
  const minScanCount = 3;
  if (rssi < rssiThreshold) {
    throw new functions.https.HttpsError("failed-precondition", `Device out of range.`);
  }
  if (scanCount < minScanCount) {
    throw new functions.https.HttpsError("failed-precondition", `Insufficient dwell-time.`);
  }

  // Lookup full UID and metadata from user details (since advertising uses 8-char prefixes)
  let targetUid = studentUid;
  let targetName = "Unknown";
  let targetRollNo = "";

  if (studentUid.length === 8) {
    const userQuery = await admin.firestore().collection("users")
      .orderBy(admin.firestore.FieldPath.documentId())
      .startAt(studentUid)
      .endAt(studentUid + "\uf8ff")
      .limit(1)
      .get();

    if (userQuery.docs.length > 0) {
      const doc = userQuery.docs[0];
      targetUid = doc.id;
      targetName = doc.data().name || "Unknown";
      targetRollNo = doc.data().rollNo || "";
    } else {
      throw new functions.https.HttpsError("not-found", `No user profile found matching prefix ${studentUid}.`);
    }
  } else {
    const userDoc = await admin.firestore().collection("users").doc(studentUid).get();
    if (userDoc.exists) {
      targetName = userDoc.data().name || "Unknown";
      targetRollNo = userDoc.data().rollNo || "";
    }
  }

  const docRef = admin.firestore()
    .collection("sessions")
    .doc(sessionId)
    .collection("attendance")
    .doc(targetUid);

  const existing = await docRef.get();
  if (existing.exists) {
    await docRef.update({
      scanCount: admin.firestore.FieldValue.increment(1),
      rssi: rssi,
      lastSeenAt: now,
    });
  } else {
    await docRef.set({
      id: targetUid,
      sessionId: sessionId,
      studentId: targetUid,
      studentName: targetName,
      rollNo: targetRollNo,
      status: "present",
      rssi: rssi,
      scanCount: scanCount,
      markedAt: now.toDate(),
    });
  }

  return { success: true, studentUid: targetUid };
});

/**
 * Callable: edits student attendance status, restricted by Faculty/Mentor roles.
 */
exports.editAttendance = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated.");
  }
  const { sessionId, studentUid, newStatus } = data;
  if (!sessionId || !studentUid || !newStatus) {
    throw new functions.https.HttpsError("invalid-argument", "Missing parameters.");
  }

  const sessionDoc = await admin.firestore().collection("sessions").doc(sessionId).get();
  if (!sessionDoc.exists) {
    throw new functions.https.HttpsError("not-found", "Session not found.");
  }
  const session = sessionDoc.data();

  const callerDoc = await admin.firestore().collection("users").doc(context.auth.uid).get();
  const callerRole = callerDoc.data() ? callerDoc.data().role : "";

  const isOwner = session.facultyId === context.auth.uid;
  const isAdmin = context.auth.token.role === "admin" || callerRole === "admin";
  const isMentor = callerRole === "mentor";

  if (!isOwner && !isAdmin && !isMentor) {
    throw new functions.https.HttpsError("permission-denied", "Unauthorized to edit attendance.");
  }

  if (newStatus === "od" && !isMentor && !isAdmin) {
    throw new functions.https.HttpsError("permission-denied", "Only mentors or admins can mark OD.");
  }

  const docRef = admin.firestore()
    .collection("sessions")
    .doc(sessionId)
    .collection("attendance")
    .doc(studentUid);

  const doc = await docRef.get();
  const oldStatus = doc.exists ? (doc.data().status || "absent") : "absent";

  const now = admin.firestore.Timestamp.now();

  if (doc.exists) {
    await docRef.update({
      status: newStatus,
      previousStatus: oldStatus,
      editedBy: context.auth.uid,
      editedAt: now,
    });
  } else {
    const studentDoc = await admin.firestore().collection("users").doc(studentUid).get();
    const studentData = studentDoc.data() || {};
    await docRef.set({
      id: studentUid,
      sessionId: sessionId,
      studentId: studentUid,
      studentName: studentData.name || "Unknown",
      rollNo: studentData.rollNo || "",
      status: newStatus,
      rssi: 0,
      scanCount: 0,
      markedAt: now.toDate(),
      editedBy: context.auth.uid,
      editedAt: now,
    });
  }

  await admin.firestore()
    .collection("sessions")
    .doc(sessionId)
    .collection("audit")
    .add({
      studentId: studentUid,
      oldStatus: oldStatus,
      newStatus: newStatus,
      editedBy: context.auth.uid,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

  return { success: true };
});

/**
 * Trigger: fires on writes to any student's attendance document.
 * Safely builds the email contents server-side and sends it via SendGrid.
 */
exports.onAttendanceWrite = functions.firestore
  .document("sessions/{sessionId}/attendance/{studentUid}")
  .onWrite(async (change, context) => {
    const { sessionId, studentUid } = context.params;
    const beforeData = change.before.exists ? change.before.data() : null;
    const afterData = change.after.exists ? change.after.data() : null;

    if (!afterData) return null; // deleted

    const oldStatus = beforeData ? beforeData.status : null;
    const newStatus = afterData.status;

    if (oldStatus === newStatus) return null;

    // Load profile info
    const studentDoc = await admin.firestore().collection("users").doc(studentUid).get();
    if (!studentDoc.exists) return null;
    const student = studentDoc.data();
    const studentEmail = student.email;
    const parentEmail = student.parentEmail;

    // Load session info
    const sessionDoc = await admin.firestore().collection("sessions").doc(sessionId).get();
    if (!sessionDoc.exists) return null;
    const session = sessionDoc.data();
    const subjectName = session.subjectName || "Unknown Subject";
    const classId = session.classId || "Unknown Class";
    const startTime = session.startTime ? session.startTime.toDate() : new Date();

    const timeStr = `${startTime.getDate()}/${startTime.getMonth() + 1}/${startTime.getFullYear()} ` +
      `${startTime.getHours()}:${startTime.getMinutes().toString().padStart(2, "0")}`;

    let subject = "";
    let body = "";

    if (newStatus === "present" || newStatus === "od") {
      subject = `Attendance Confirmed: ${subjectName}`;
      body = `Attendance Confirmed\n\nSubject: ${subjectName}\nClass: ${classId}\nTime: ${timeStr}\nStatus: ${newStatus.toUpperCase()} ✓\n\nYour attendance has been successfully recorded.`;
    } else if (newStatus === "absent") {
      subject = `Attendance Missed: ${subjectName}`;
      body = `Attendance Missed\n\nSubject: ${subjectName}\nClass: ${classId}\nTime: ${timeStr}\nStatus: ABSENT ✗\n\nYou were not detected or marked absent for this session.`;
    } else {
      return null; // unsupported status
    }

    const recipients = [studentEmail];
    if (parentEmail && parentEmail.length > 0) {
      recipients.push(parentEmail);
    }

    const msg = {
      to: recipients,
      from: "attendance@yourcollege.edu.in",
      subject: subject,
      text: body,
      html: `<pre>${body}</pre>`,
    };

    try {
      await sgMail.send(msg);
      console.log(`Notification sent for ${studentUid} (${newStatus})`);

      // Log notification record for history
      await admin.firestore().collection("notifications").add({
        type: "attendance",
        studentUid: studentUid,
        subject: subject,
        body: body,
        status: "sent",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (error) {
      console.error("SendGrid notification error:", error);
    }

    return null;
  });

/**
 * Scheduled function: auto-expires passed sessions every 1 minute.
 */
exports.expireSessions = functions.pubsub
  .schedule("every 1 minutes")
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();
    const sessionsRef = admin.firestore().collection("sessions");
    const expiredSessions = await sessionsRef
      .where("status", "==", "active")
      .where("endTime", "<=", now)
      .get();

    const batch = admin.firestore().batch();
    expiredSessions.forEach((doc) => {
      batch.update(doc.ref, { status: "expired" });
    });

    await batch.commit();
    console.log(`Expired ${expiredSessions.size} sessions.`);
    return null;
  });
