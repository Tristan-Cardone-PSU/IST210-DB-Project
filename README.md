# Shodan Karate School Manager

A local web app for managing Shodan Karate student records stored in Azure SQL. Azure SQL is the system of record; the app connects to the existing cloud database and reads or updates its school records. The app includes a live student roster, class attendance, belt test history, parent and guardian details, billing, and class schedules. Vehicle and dispatch management has been removed.

## Start the app

Run `start-server.bat`, then open [http://localhost:8080](http://localhost:8080). The login screen asks for the Azure SQL server, database, SQL login, and password. `LOGIN_INFO.txt` contains the connection details currently configured for this project. The browser talks to the local PowerShell bridge, which opens encrypted connections to the cloud SQL database. The local bridge serves the app; it does not store school data locally.

The app expects the school tables described in `karate-schema.sql` to already exist in the connected Azure SQL database. For an existing database, run `allow-unassigned-class.sql` once in Azure Data Studio or SSMS before using the “No class” option or deleting a class. This makes enrollment and attendance class links nullable while preserving their records. The app does not apply schema changes; they must be run against Azure SQL separately.

## School workflows

- Enroll students, optionally assign a class and a primary parent or guardian.
- Create and read class, student, and family records; edit class schedules, student profiles and placement, and family billing/contact details.
- Remove a student with confirmation; linked enrollment, family-link, test, and attendance rows are removed in the same transaction. Parent deletion is blocked while student links remain. Azure SQL foreign keys configured with `ON DELETE NO ACTION` remain in place.
- Unassign a student by editing the student and choosing “No class.” A class cannot be deleted while current student assignments remain. After unassignment, deleting the class keeps enrollment and attendance history but sets those history rows’ `ClassID` values to `NULL`.
- Store parent contact, mailing address, billing method, and monthly rate.
- Record attendance by class and date, with Present, Absent, and Excused statuses.
- Record belt attempts, scores, pass results, and instructor notes. Test history is marked locked in the database schema.
- Track the black belt waiting start and testing status on student records.
- Manage programs and age groups: Little Ninjas (4–6), Youth (7–13), Adult (13+), and Kickboxing (18+).


