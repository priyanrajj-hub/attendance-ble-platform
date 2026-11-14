const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const firebase = require('firebase/compat/app');
require('firebase/compat/firestore');
const { readFileSync } = require('fs');

const serverTimestamp = () => firebase.firestore.FieldValue.serverTimestamp();

let testEnv;

before(async () => {
    testEnv = await initializeTestEnvironment({
        projectId: 'attendance-ble-app-test',
        firestore: {
            rules: readFileSync('../firestore.rules', 'utf8'),
            host: '127.0.0.1',
            port: 8080,
        },
    });
});

after(async () => {
    if (testEnv) {
        await testEnv.cleanup();
    }
});

beforeEach(async () => {
    await testEnv.clearFirestore();

    // Seed baseline entities using disabled security rules
    await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        const now = new Date();

        // 1. Admin
        await db.collection('users').doc('admin1').set({
            name: 'Chief Admin',
            email: 'admin@ch.amrita.edu',
            role: 'admin',
            status: 'verified',
            createdAt: now,
        });

        // 2. Verified Faculty
        await db.collection('users').doc('faculty1').set({
            name: 'Prof. Faculty One',
            email: 'fac1@ch.amrita.edu',
            role: 'faculty',
            status: 'verified',
            createdAt: now,
        });

        // 3. Other Faculty
        await db.collection('users').doc('faculty2').set({
            name: 'Prof. Faculty Two',
            email: 'fac2@ch.amrita.edu',
            role: 'faculty',
            status: 'verified',
            createdAt: now,
        });

        // 4. Verified Student with bound device
        await db.collection('users').doc('student1').set({
            name: 'Student One',
            email: 'stu1@ch.students.amrita.edu',
            role: 'student',
            status: 'verified',
            rollNo: 'AM.EN.U4CSE21001',
            deviceId: 'device-uuid-stu1',
            createdAt: now,
        });

        // 5. Verified Student without device
        await db.collection('users').doc('student2').set({
            name: 'Student Two',
            email: 'stu2@ch.students.amrita.edu',
            role: 'student',
            status: 'verified',
            rollNo: 'AM.EN.U4CSE21002',
            createdAt: now,
        });

        // 6. Course assigned to faculty1
        await db.collection('courses').doc('CSE450').set({
            code: '19CSE450',
            title: 'Mobile Computing',
            room: 'Room 204',
            facultyIds: ['faculty1'],
        });

        // 7. Enrollment for student1 in CSE450
        await db.collection('enrollments').doc('CSE450_student1').set({
            courseId: 'CSE450',
            studentUid: 'student1',
            studentName: 'Student One',
            rollNo: 'AM.EN.U4CSE21001',
            enrolledAt: now,
        });
    });
});

describe('Phase 3 Comprehensive Firestore Security Rules Suite', () => {

    // ── Suite 1: User Registration ───────────────────────────────────────────
    describe('1. User Registration (users/{uid} create)', () => {
        it('allows student registration with official domain and valid keys', async () => {
            const ctx = testEnv.authenticatedContext('newStudent', {
                email: 'newstu@ch.students.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertSucceeds(db.collection('users').doc('newStudent').set({
                name: 'New Student',
                email: 'newstu@ch.students.amrita.edu',
                role: 'student',
                status: 'pending_verification',
                rollNo: 'AM.EN.U4CSE21050',
                createdAt: serverTimestamp(),
            }));
        });

        it('allows faculty registration with official domain and valid keys', async () => {
            const ctx = testEnv.authenticatedContext('newFaculty', {
                email: 'newfac@ch.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertSucceeds(db.collection('users').doc('newFaculty').set({
                name: 'New Faculty',
                email: 'newfac@ch.amrita.edu',
                role: 'faculty',
                status: 'pending_verification',
                createdAt: serverTimestamp(),
            }));
        });

        it('denies registration when createdAt is not request.time', async () => {
            const ctx = testEnv.authenticatedContext('badTimeUser', {
                email: 'badtime@ch.students.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertFails(db.collection('users').doc('badTimeUser').set({
                name: 'Bad Time',
                email: 'badtime@ch.students.amrita.edu',
                role: 'student',
                status: 'pending_verification',
                createdAt: new Date(Date.now() - 60000), // forged client timestamp
            }));
        });

        it('denies registration with commercial/personal domain', async () => {
            const ctx = testEnv.authenticatedContext('badEmailUser', {
                email: 'attacker@gmail.com',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertFails(db.collection('users').doc('badEmailUser').set({
                name: 'Bad Email',
                email: 'attacker@gmail.com',
                role: 'student',
                status: 'pending_verification',
                createdAt: serverTimestamp(),
            }));
        });

        it('denies registration self-assigning role admin', async () => {
            const ctx = testEnv.authenticatedContext('fakeAdmin', {
                email: 'fakeadmin@ch.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertFails(db.collection('users').doc('fakeAdmin').set({
                name: 'Fake Admin',
                email: 'fakeadmin@ch.amrita.edu',
                role: 'admin',
                status: 'pending_verification',
                createdAt: serverTimestamp(),
            }));
        });

        it('denies registration with extra/forbidden keys (verifiedBy, fullName)', async () => {
            const ctx = testEnv.authenticatedContext('extraKeysUser', {
                email: 'extra@ch.students.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertFails(db.collection('users').doc('extraKeysUser').set({
                name: 'Extra Keys',
                fullName: 'Extra Keys',
                email: 'extra@ch.students.amrita.edu',
                role: 'student',
                status: 'pending_verification',
                verifiedBy: 'admin1',
                createdAt: serverTimestamp(),
            }));
        });

        it('denies registration with status other than pending_verification', async () => {
            const ctx = testEnv.authenticatedContext('selfVerified', {
                email: 'selfver@ch.students.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertFails(db.collection('users').doc('selfVerified').set({
                name: 'Self Verified',
                email: 'selfver@ch.students.amrita.edu',
                role: 'student',
                status: 'verified',
                createdAt: serverTimestamp(),
            }));
        });
    });

    // ── Suite 2: Self-Service Profile Updates & Device Binding ───────────────
    describe('2. Profile Updates and Device Binding', () => {
        it('allows student to set deviceId exactly once', async () => {
            const ctx = testEnv.authenticatedContext('student2', {
                email: 'stu2@ch.students.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertSucceeds(db.collection('users').doc('student2').update({
                deviceId: 'unique-device-uuid-stu2',
            }));
        });

        it('denies student rewriting existing deviceId', async () => {
            const ctx = testEnv.authenticatedContext('student1', {
                email: 'stu1@ch.students.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertFails(db.collection('users').doc('student1').update({
                deviceId: 'new-forged-device-id',
            }));
        });

        it('denies user changing their own role or status', async () => {
            const ctx = testEnv.authenticatedContext('student1', {
                email: 'stu1@ch.students.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertFails(db.collection('users').doc('student1').update({
                status: 'verified',
                role: 'faculty',
            }));
        });
    });

    // ── Suite 3: Admin Approvals & Stamps ────────────────────────────────────
    describe('3. Admin Approvals and Review Operations', () => {
        beforeEach(async () => {
            await testEnv.withSecurityRulesDisabled(async (context) => {
                const db = context.firestore();
                await db.collection('users').doc('pendingUser').set({
                    name: 'Pending User',
                    email: 'pen@ch.students.amrita.edu',
                    role: 'student',
                    status: 'pending_verification',
                    createdAt: new Date(),
                });
            });
        });

        it('allows admin to approve pending user with verifiedBy and verifiedAt stamps', async () => {
            const ctx = testEnv.authenticatedContext('admin1', {
                email: 'admin@ch.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertSucceeds(db.collection('users').doc('pendingUser').update({
                status: 'verified',
                verifiedBy: 'admin1',
                verifiedAt: serverTimestamp(),
            }));
        });

        it('denies admin approval without stamping verifiedBy/verifiedAt', async () => {
            const ctx = testEnv.authenticatedContext('admin1', {
                email: 'admin@ch.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertFails(db.collection('users').doc('pendingUser').update({
                status: 'verified',
            }));
        });

        it('denies non-admin from approving users', async () => {
            const ctx = testEnv.authenticatedContext('faculty1', {
                email: 'fac1@ch.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertFails(db.collection('users').doc('pendingUser').update({
                status: 'verified',
                verifiedBy: 'faculty1',
                verifiedAt: serverTimestamp(),
            }));
        });

        it('denies admin from modifying another admin doc', async () => {
            await testEnv.withSecurityRulesDisabled(async (context) => {
                await context.firestore().collection('users').doc('admin2').set({
                    name: 'Second Admin',
                    email: 'admin2@ch.amrita.edu',
                    role: 'admin',
                    status: 'verified',
                    createdAt: new Date(),
                });
            });

            const ctx = testEnv.authenticatedContext('admin1', {
                email: 'admin@ch.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertFails(db.collection('users').doc('admin2').update({
                status: 'suspended',
                verifiedBy: 'admin1',
                verifiedAt: serverTimestamp(),
            }));
        });
    });

    // ── Suite 4: Email Verification Gate ─────────────────────────────────────
    describe('4. Unverified Email Access Denial', () => {
        it('allows unverified user to read their own profile', async () => {
            const ctx = testEnv.authenticatedContext('student1', {
                email: 'stu1@ch.students.amrita.edu',
                email_verified: false,
            });
            const db = ctx.firestore();
            await assertSucceeds(db.collection('users').doc('student1').get());
        });

        it('denies unverified user from reading courses', async () => {
            const ctx = testEnv.authenticatedContext('student1', {
                email: 'stu1@ch.students.amrita.edu',
                email_verified: false,
            });
            const db = ctx.firestore();
            await assertFails(db.collection('courses').doc('CSE450').get());
        });
    });

    // ── Suite 5: Course & Enrollment CRUD ────────────────────────────────────
    describe('5. Courses and Enrollments Scoping', () => {
        it('allows admin to create courses', async () => {
            const ctx = testEnv.authenticatedContext('admin1', {
                email: 'admin@ch.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertSucceeds(db.collection('courses').doc('CSE401').set({
                code: '19CSE401',
                title: 'Distributed Systems',
                room: 'Lab 3',
                facultyIds: ['faculty1'],
            }));
        });

        it('denies faculty from creating courses', async () => {
            const ctx = testEnv.authenticatedContext('faculty1', {
                email: 'fac1@ch.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertFails(db.collection('courses').doc('CSE999').set({
                code: '19CSE999',
                title: 'Hacked Course',
                room: 'Room 101',
                facultyIds: ['faculty1'],
            }));
        });

        it('allows assigned faculty to read course', async () => {
            const ctx = testEnv.authenticatedContext('faculty1', {
                email: 'fac1@ch.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertSucceeds(db.collection('courses').doc('CSE450').get());
        });

        it('denies unassigned faculty from reading course', async () => {
            const ctx = testEnv.authenticatedContext('faculty2', {
                email: 'fac2@ch.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertFails(db.collection('courses').doc('CSE450').get());
        });
    });

    // ── Suite 6: Session Creation ────────────────────────────────────────────
    describe('6. Faculty Attendance Session Creation', () => {
        it('allows faculty to create session for their assigned course (<= 30 min)', async () => {
            const ctx = testEnv.authenticatedContext('faculty1', {
                email: 'fac1@ch.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            const endsAt = new Date(Date.now() + 15 * 60 * 1000); // 15 mins

            await assertSucceeds(db.collection('sessions').doc('session1').set({
                courseId: 'CSE450',
                facultyId: 'faculty1',
                startedAt: serverTimestamp(),
                endsAt: endsAt,
                status: 'open',
            }));
        });

        it('allows faculty to project PostgreSQL session with backendSessionId', async () => {
            const ctx = testEnv.authenticatedContext('faculty1', {
                email: 'fac1@ch.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            const endsAt = new Date(Date.now() + 15 * 60 * 1000);

            await assertSucceeds(db.collection('sessions').doc('00000000-0000-0000-0000-000000000001').set({
                courseId: 'CSE450',
                facultyId: 'faculty1',
                startedAt: serverTimestamp(),
                endsAt: endsAt,
                status: 'open',
                backendSessionId: '00000000-0000-0000-0000-000000000001',
            }));
        });

        it('denies faculty creating session for unassigned course', async () => {
            const ctx = testEnv.authenticatedContext('faculty2', {
                email: 'fac2@ch.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            const endsAt = new Date(Date.now() + 15 * 60 * 1000);

            await assertFails(db.collection('sessions').doc('sessionBadCourse').set({
                courseId: 'CSE450',
                facultyId: 'faculty2',
                startedAt: serverTimestamp(),
                endsAt: endsAt,
                status: 'open',
            }));
        });

        it('denies session creation with duration > 30 minutes', async () => {
            const ctx = testEnv.authenticatedContext('faculty1', {
                email: 'fac1@ch.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            const endsAt = new Date(Date.now() + 45 * 60 * 1000); // 45 mins > 30 min limit

            await assertFails(db.collection('sessions').doc('sessionTooLong').set({
                courseId: 'CSE450',
                facultyId: 'faculty1',
                startedAt: serverTimestamp(),
                endsAt: endsAt,
                status: 'open',
            }));
        });
    });

    // ── Suite 7: Live Nonce Rotation Subcollection ───────────────────────────
    describe('7. Rotating Beacon Secrets (sessions/{sid}/live/current)', () => {
        beforeEach(async () => {
            await testEnv.withSecurityRulesDisabled(async (context) => {
                const db = context.firestore();
                const now = new Date();
                await db.collection('sessions').doc('sessionOpen').set({
                    courseId: 'CSE450',
                    facultyId: 'faculty1',
                    startedAt: now,
                    endsAt: new Date(now.getTime() + 20 * 60 * 1000),
                    status: 'open',
                });
            });
        });

        it('allows faculty owner to write rotating 8-hex code', async () => {
            const ctx = testEnv.authenticatedContext('faculty1', {
                email: 'fac1@ch.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertSucceeds(db.collection('sessions').doc('sessionOpen').collection('live').doc('current').set({
                code: 'a1b2c3d4',
                prevCode: '00000000',
                rotatedAt: serverTimestamp(),
            }));
        });

        it('allows faculty owner to write rotating 32-hex 128-bit challenge code', async () => {
            const ctx = testEnv.authenticatedContext('faculty1', {
                email: 'fac1@ch.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertSucceeds(db.collection('sessions').doc('sessionOpen').collection('live').doc('current').set({
                code: '4f5a8b2c1d3e9f0a5b6c7d8e9f0a1b2c',
                prevCode: '1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d',
                rotatedAt: serverTimestamp(),
            }));
        });

        it('denies student reading live/current secret document', async () => {
            const ctx = testEnv.authenticatedContext('student1', {
                email: 'stu1@ch.students.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertFails(db.collection('sessions').doc('sessionOpen').collection('live').doc('current').get());
        });

        it('denies non-owner faculty from writing live/current', async () => {
            const ctx = testEnv.authenticatedContext('faculty2', {
                email: 'fac2@ch.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertFails(db.collection('sessions').doc('sessionOpen').collection('live').doc('current').set({
                code: 'deadbeef',
                rotatedAt: serverTimestamp(),
            }));
        });
    });

    // ── Suite 8: Student Check-in Verification ───────────────────────────────
    describe('8. Student Check-in Verification (sessions/{sid}/attendance/{uid})', () => {
        beforeEach(async () => {
            await testEnv.withSecurityRulesDisabled(async (context) => {
                const db = context.firestore();
                const now = new Date();
                await db.collection('sessions').doc('sessionOpen').set({
                    courseId: 'CSE450',
                    facultyId: 'faculty1',
                    startedAt: now,
                    endsAt: new Date(now.getTime() + 20 * 60 * 1000),
                    status: 'open',
                });

                await db.collection('sessions').doc('sessionOpen').collection('live').doc('current').set({
                    code: '12345678',
                    prevCode: '87654321',
                    rotatedAt: now,
                });
            });
        });

        it('denies direct student check-in writes to Firestore (PostgreSQL authority is enforced)', async () => {
            const ctx = testEnv.authenticatedContext('student1', {
                email: 'stu1@ch.students.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertFails(db.collection('sessions').doc('sessionOpen').collection('attendance').doc('student1').set({
                studentUid: 'student1',
                markedAt: serverTimestamp(),
                method: 'ble',
                code: '12345678',
                rssi: -65,
                deviceId: 'device-uuid-stu1',
            }));
        });

        it('denies direct student check-in with prevCode to Firestore', async () => {
            const ctx = testEnv.authenticatedContext('student1', {
                email: 'stu1@ch.students.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertFails(db.collection('sessions').doc('sessionOpen').collection('attendance').doc('student1').set({
                studentUid: 'student1',
                markedAt: serverTimestamp(),
                method: 'ble',
                code: '87654321',
                rssi: -70,
                deviceId: 'device-uuid-stu1',
            }));
        });

        it('denies check-in with invalid/expired nonce code', async () => {
            const ctx = testEnv.authenticatedContext('student1', {
                email: 'stu1@ch.students.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertFails(db.collection('sessions').doc('sessionOpen').collection('attendance').doc('student1').set({
                studentUid: 'student1',
                markedAt: serverTimestamp(),
                method: 'ble',
                code: '99999999', // wrong code
                rssi: -65,
                deviceId: 'device-uuid-stu1',
            }));
        });

        it('denies check-in with mismatched deviceId', async () => {
            const ctx = testEnv.authenticatedContext('student1', {
                email: 'stu1@ch.students.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertFails(db.collection('sessions').doc('sessionOpen').collection('attendance').doc('student1').set({
                studentUid: 'student1',
                markedAt: serverTimestamp(),
                method: 'ble',
                code: '12345678',
                rssi: -65,
                deviceId: 'wrong-friend-device-id',
            }));
        });

        it('denies check-in for unenrolled student', async () => {
            const ctx = testEnv.authenticatedContext('student2', {
                email: 'stu2@ch.students.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertFails(db.collection('sessions').doc('sessionOpen').collection('attendance').doc('student2').set({
                studentUid: 'student2',
                markedAt: serverTimestamp(),
                method: 'ble',
                code: '12345678',
                rssi: -65,
                deviceId: 'device-uuid-stu2',
            }));
        });
    });

    // ── Suite 9: Faculty Manual Override ─────────────────────────────────────
    describe('9. Faculty Manual Override (Authoritative Backend Only)', () => {
        beforeEach(async () => {
            await testEnv.withSecurityRulesDisabled(async (context) => {
                const db = context.firestore();
                const now = new Date();
                await db.collection('sessions').doc('sessionOpen').set({
                    courseId: 'CSE450',
                    facultyId: 'faculty1',
                    startedAt: now,
                    endsAt: new Date(now.getTime() + 20 * 60 * 1000),
                    status: 'open',
                });
            });
        });

        it('denies direct client manual override writes to Firestore (must route through FastAPI backend)', async () => {
            const ctx = testEnv.authenticatedContext('faculty1', {
                email: 'fac1@ch.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertFails(db.collection('sessions').doc('sessionOpen').collection('attendance').doc('student1').set({
                studentUid: 'student1',
                markedAt: serverTimestamp(),
                method: 'manual',
                markedBy: 'faculty1',
                reason: 'Student present but Bluetooth radio damaged',
            }));
        });

        it('denies manual override without required reason', async () => {
            const ctx = testEnv.authenticatedContext('faculty1', {
                email: 'fac1@ch.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertFails(db.collection('sessions').doc('sessionOpen').collection('attendance').doc('student1').set({
                studentUid: 'student1',
                markedAt: serverTimestamp(),
                method: 'manual',
                markedBy: 'faculty1',
            }));
        });

        it('denies non-owning faculty manual override', async () => {
            const ctx = testEnv.authenticatedContext('faculty2', {
                email: 'fac2@ch.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertFails(db.collection('sessions').doc('sessionOpen').collection('attendance').doc('student1').set({
                studentUid: 'student1',
                markedAt: serverTimestamp(),
                method: 'manual',
                markedBy: 'faculty2',
                reason: 'Attempted override by other faculty',
            }));
        });

        it('allows server-side Admin SDK writes and permits owning faculty to read attendance projection', async () => {
            await testEnv.withSecurityRulesDisabled(async (context) => {
                const db = context.firestore();
                await db.collection('sessions').doc('sessionOpen').collection('attendance').doc('student1').set({
                    studentUid: 'student1',
                    markedAt: new Date(),
                    method: 'faculty_manual_override',
                    markedBy: 'faculty1',
                    reason: 'Verified present via backend manual override',
                });
            });

            const ctx = testEnv.authenticatedContext('faculty1', {
                email: 'fac1@ch.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertSucceeds(db.collection('sessions').doc('sessionOpen').collection('attendance').doc('student1').get());
        });
    });

    // ── Suite 10: Collection Group History ───────────────────────────────────
    describe('10. Collection-Group Attendance History', () => {
        beforeEach(async () => {
            await testEnv.withSecurityRulesDisabled(async (context) => {
                const db = context.firestore();
                const now = new Date();
                await db.collection('sessions').doc('sessA').collection('attendance').doc('student1').set({
                    studentUid: 'student1',
                    markedAt: now,
                    method: 'ble',
                    code: '12345678',
                    rssi: -60,
                });
                await db.collection('sessions').doc('sessA').collection('attendance').doc('student2').set({
                    studentUid: 'student2',
                    markedAt: now,
                    method: 'ble',
                    code: '12345678',
                    rssi: -62,
                });
            });
        });

        it('allows student to query their own collection-group attendance rows', async () => {
            const ctx = testEnv.authenticatedContext('student1', {
                email: 'stu1@ch.students.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertSucceeds(
                db.collectionGroup('attendance').where('studentUid', '==', 'student1').get()
            );
        });

        it('denies student querying other students rows in collection-group', async () => {
            const ctx = testEnv.authenticatedContext('student1', {
                email: 'stu1@ch.students.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertFails(
                db.collectionGroup('attendance').where('studentUid', '==', 'student2').get()
            );
        });
    });

    // ── Suite 11: Default Deny ───────────────────────────────────────────────
    describe('11. Default Deny On Unknown Paths', () => {
        it('denies writes to unknown top-level collection', async () => {
            const ctx = testEnv.authenticatedContext('student1', {
                email: 'stu1@ch.students.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertFails(db.collection('audit_logs').doc('log1').set({
                action: 'hack',
            }));
        });

        it('denies reads from unknown top-level collection', async () => {
            const ctx = testEnv.authenticatedContext('admin1', {
                email: 'admin@ch.amrita.edu',
                email_verified: true,
            });
            const db = ctx.firestore();
            await assertFails(db.collection('secret_audit').doc('log1').get());
        });
    });
});
