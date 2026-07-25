const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { readFileSync } = require('fs');

let testEnv;

before(async () => {
    // Initialize the emulator environment.
    testEnv = await initializeTestEnvironment({
        projectId: 'attendance-ble-app-test',
        firestore: {
            rules: readFileSync('../firestore.rules', 'utf8'),
            host: '127.0.0.1',
            port: 8080,
        },
    });
});

beforeEach(async () => {
    await testEnv.clearFirestore();

    // Set up mock users for reading tests
    await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        await db.collection('users').doc('studentA').set({
            role: 'student', email: 'a@ch.en.students.amrita.edu', status: 'pending_verification'
        });
        await db.collection('users').doc('studentB').set({
            role: 'student', email: 'b@ch.en.students.amrita.edu', status: 'pending_verification'
        });
        await db.collection('users').doc('facultyA').set({
            role: 'faculty', email: 'c@ch.amrita.edu', status: 'pending_verification'
        });
        await db.collection('users').doc('adminA').set({
            role: 'admin', email: 'admin@ch.amrita.edu', status: 'verified'
        });
    });
});

afterEach(async () => {
    await testEnv.clearFirestore();
});

after(async () => {
    await testEnv.cleanup();
});

describe('Firestore Security Rules', () => {

    it('Student A cannot read Student B doc, but can read their own', async () => {
        const studentAContext = testEnv.authenticatedContext('studentA', { email_verified: true });
        const db = studentAContext.firestore();

        // Should succeed reading their own doc
        await assertSucceeds(db.collection('users').doc('studentA').get());
        // Should fail reading Student B's doc
        await assertFails(db.collection('users').doc('studentB').get());
    });

    it('Faculty can read a student doc, but CANNOT read other faculty/admin docs (Restricted for privacy)', async () => {
        const facultyAContext = testEnv.authenticatedContext('facultyA', { email_verified: true });
        const db = facultyAContext.firestore();

        // Faculty reading student A
        await assertSucceeds(db.collection('users').doc('studentA').get());
        // Faculty reading an admin (should fail due to resource.data.role == 'student' restriction)
        await assertFails(db.collection('users').doc('adminA').get());
    });

    it('Student cannot write to attendance/{their own uid}', async () => {
        const studentAContext = testEnv.authenticatedContext('studentA', { email_verified: true });
        const db = studentAContext.firestore();

        // They are trying to mark themselves present
        await assertFails(db.collection('sessions').doc('sessionX').collection('attendance').doc('studentA').set({
            present: true
        }));
    });

    it('Only the owning faculty (or admin) can write attendance', async () => {
        // First, create a session owned by facultyA
        await testEnv.withSecurityRulesDisabled(async (context) => {
            const db = context.firestore();
            await db.collection('sessions').doc('sessionX').set({
                facultyId: 'facultyA',
            });
        });

        const facultyAContext = testEnv.authenticatedContext('facultyA', { email_verified: true });
        const dbFaculty = facultyAContext.firestore();

        // Faculty marking studentA present should succeed
        await assertSucceeds(dbFaculty.collection('sessions').doc('sessionX').collection('attendance').doc('studentA').set({
            present: true
        }));

        // Admin should also succeed
        const adminAContext = testEnv.authenticatedContext('adminA', { email_verified: true });
        const dbAdmin = adminAContext.firestore();
        await assertSucceeds(dbAdmin.collection('sessions').doc('sessionX').collection('attendance').doc('studentB').set({
            present: true
        }));

        // A DIFFERENT faculty should fail
        const facultyBContext = testEnv.authenticatedContext('facultyB', { email_verified: true });
        await testEnv.withSecurityRulesDisabled(async (context) => {
            await context.firestore().collection('users').doc('facultyB').set({ role: 'faculty' });
        });
        const dbFacultyB = facultyBContext.firestore();
        await assertFails(dbFacultyB.collection('sessions').doc('sessionX').collection('attendance').doc('studentA').set({
            present: true
        }));
    });

    it('Unverified user is blocked from sessions reads', async () => {
        const unverifiedContext = testEnv.authenticatedContext('studentA', { email_verified: false }); // Unverified token
        const db = unverifiedContext.firestore();

        await assertFails(db.collection('sessions').doc('sessionX').get());
    });

    it('User creation fails if status != pending_verification or if email domain doesn\'t match role', async () => {
        const newStudentContext = testEnv.authenticatedContext('studentNew', { email: 'new@ch.en.students.amrita.edu', email_verified: false });
        const db = newStudentContext.firestore();

        // 1. Success matching exact role and status
        await assertSucceeds(db.collection('users').doc('studentNew').set({
            role: 'student',
            email: 'new@ch.en.students.amrita.edu',
            status: 'pending_verification',
            name: 'Bob',
            rollNo: '123'
        }));

        // 2. Failure: status is not pending_verification (e.g. they forge "verified")
        const badStatusContext = testEnv.authenticatedContext('studentBadStats', { email: 'bad@ch.en.students.amrita.edu' });
        await assertFails(badStatusContext.firestore().collection('users').doc('studentBadStats').set({
            role: 'student',
            email: 'bad@ch.en.students.amrita.edu',
            status: 'verified',
            name: 'Bob',
            rollNo: '123'
        }));

        // 3. Failure: email domain does not match role (Student role with Faculty email)
        const badRoleContext = testEnv.authenticatedContext('facultyBadRole', { email: 'faculty@ch.amrita.edu' });
        await assertFails(badRoleContext.firestore().collection('users').doc('facultyBadRole').set({
            role: 'student',
            email: 'faculty@ch.amrita.edu',
            status: 'pending_verification',
            name: 'Bob',
            rollNo: '123'
        }));

        // 4. Failure: Student email lacks correct domain completely
        const gmailContext = testEnv.authenticatedContext('studentGmail', { email: 'bob@gmail.com' });
        await assertFails(gmailContext.firestore().collection('users').doc('studentGmail').set({
            role: 'student',
            email: 'bob@gmail.com',
            status: 'pending_verification',
            name: 'Bob',
            rollNo: '123'
        }));
    });
});
