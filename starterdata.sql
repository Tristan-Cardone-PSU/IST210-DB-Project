/*
    SHODAN KARATE STARTER DATABASE SCRIPT
    =====================================

    WHAT THIS SCRIPT DOES
    Creates the empty tables the school app needs in Azure SQL. It does not
    add sample students, families, attendance, or test scores.

    HOW TO RUN IT
    1. Open SQL Server Management Studio (SSMS) or Azure Data Studio.
    2. Connect to the Azure SQL server and select the school's database.
    3. Open this file and run the whole script.

    A FEW SQL WORDS IN PLAIN LANGUAGE
    - A table is like a spreadsheet: it stores rows of related information.
    - A primary key (PK) is the unique ID for each row.
    - A foreign key (FK) links a row to a related row in another table.
    - NOT NULL means a value is required. NULL means it may be left blank.
    - DEFAULT supplies a value when an import does not provide one.
    - GO marks the end of a section that SQL Server runs as a unit.
    - IF OBJECT_ID ... IS NULL means “create this table only if it is missing.”

    IMPORT ORDER
    Import classes, parents, and students first. Then import the links between
    students and parents, enrollments, belt tests, and attendance. The linked
    records need their related rows to exist first.

    The app does not run this script. It only connects to the cloud database.
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* PARENTS: contact, address, and billing information for a family member. */
IF OBJECT_ID(N'dbo.Parent', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Parent (
        -- IDENTITY makes SQL Server assign a new ParentID automatically.
        ParentID       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Parent PRIMARY KEY,
        FirstName      NVARCHAR(60) NOT NULL,
        LastName       NVARCHAR(60) NOT NULL,
        Phone          NVARCHAR(20) NOT NULL,
        Email          NVARCHAR(120) NOT NULL,
        Address        NVARCHAR(200) NOT NULL,
        City           NVARCHAR(60) NOT NULL,
        State          NVARCHAR(30) NOT NULL,
        ZipCode        NVARCHAR(10) NOT NULL,
        -- These defaults are starting values; change them to match school policy.
        BillingMethod  NVARCHAR(30) NOT NULL CONSTRAINT DF_Parent_BillingMethod DEFAULT (N'Monthly'),
        MonthlyRate    DECIMAL(8,2) NOT NULL CONSTRAINT DF_Parent_MonthlyRate DEFAULT (80.00),
        CreatedAt      DATETIME2 NOT NULL CONSTRAINT DF_Parent_CreatedAt DEFAULT (SYSUTCDATETIME())
    );
END;
GO

/* STUDENTS: student profile, current rank, and black belt tracking dates. */
IF OBJECT_ID(N'dbo.Student', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Student (
        StudentID              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Student PRIMARY KEY,
        FirstName              NVARCHAR(60) NOT NULL,
        LastName               NVARCHAR(60) NOT NULL,
        DateOfBirth            DATE NOT NULL,
        BeltRank               NVARCHAR(40) NOT NULL CONSTRAINT DF_Student_BeltRank DEFAULT (N'White'),
        EnrollmentDate         DATE NOT NULL CONSTRAINT DF_Student_EnrollmentDate DEFAULT (CONVERT(DATE, SYSUTCDATETIME())),
        IsActive               BIT NOT NULL CONSTRAINT DF_Student_IsActive DEFAULT (1),
        BlackBeltWaitingStart  DATE NULL,
        IsInBlackBeltTesting   BIT NOT NULL CONSTRAINT DF_Student_IsInBlackBeltTesting DEFAULT (0),
        Notes                  NVARCHAR(MAX) NULL,
        CreatedAt              DATETIME2 NOT NULL CONSTRAINT DF_Student_CreatedAt DEFAULT (SYSUTCDATETIME())
    );
END;
GO

/* CLASSES: program name, eligible ages, schedule, instructor, and capacity. */
IF OBJECT_ID(N'dbo.Class', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Class (
        ClassID         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Class PRIMARY KEY,
        ClassName       NVARCHAR(80) NOT NULL,
        AgeGroupMin     INT NOT NULL,
        AgeGroupMax     INT NOT NULL,
        Schedule        NVARCHAR(100) NOT NULL,
        InstructorName  NVARCHAR(100) NOT NULL CONSTRAINT DF_Class_InstructorName DEFAULT (N'Sensei Cardone'),
        MaxCapacity     INT NOT NULL CONSTRAINT DF_Class_MaxCapacity DEFAULT (20),
        IsActive        BIT NOT NULL CONSTRAINT DF_Class_IsActive DEFAULT (1),
        -- CHECK rules reject age ranges or class capacities that do not make sense.
        CONSTRAINT CK_Class_AgeRange CHECK (AgeGroupMin >= 0 AND AgeGroupMax >= AgeGroupMin),
        CONSTRAINT CK_Class_MaxCapacity CHECK (MaxCapacity > 0)
    );
END;
GO

/* STUDENT-PARENT LINK: lets one student have one or two parent/guardian links. */
IF OBJECT_ID(N'dbo.StudentParent', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.StudentParent (
        StudentID        INT NOT NULL,
        ParentID         INT NOT NULL,
        Relationship     NVARCHAR(30) NOT NULL CONSTRAINT DF_StudentParent_Relationship DEFAULT (N'Parent'),
        IsPrimaryContact BIT NOT NULL CONSTRAINT DF_StudentParent_IsPrimaryContact DEFAULT (1),
        CONSTRAINT PK_StudentParent PRIMARY KEY (StudentID, ParentID),
        -- These foreign keys prevent links to students or parents that do not exist.
        CONSTRAINT FK_StudentParent_Student FOREIGN KEY (StudentID)
            REFERENCES dbo.Student(StudentID) ON DELETE NO ACTION,
        CONSTRAINT FK_StudentParent_Parent FOREIGN KEY (ParentID)
            REFERENCES dbo.Parent(ParentID) ON DELETE NO ACTION
    );
END;
GO

/* ENROLLMENTS: records which class a student is in now or attended before. */
IF OBJECT_ID(N'dbo.Enrollment', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Enrollment (
        EnrollmentID        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Enrollment PRIMARY KEY,
        StudentID           INT NOT NULL,
        -- NULL means the student is currently unassigned to a class.
        ClassID             INT NULL,
        EnrolledDate        DATE NOT NULL CONSTRAINT DF_Enrollment_EnrolledDate DEFAULT (CONVERT(DATE, SYSUTCDATETIME())),
        IsCurrentEnrollment BIT NOT NULL CONSTRAINT DF_Enrollment_IsCurrentEnrollment DEFAULT (1),
        CONSTRAINT FK_Enrollment_Student FOREIGN KEY (StudentID)
            REFERENCES dbo.Student(StudentID) ON DELETE NO ACTION,
        CONSTRAINT FK_Enrollment_Class FOREIGN KEY (ClassID)
            REFERENCES dbo.Class(ClassID) ON DELETE NO ACTION
    );
END;
GO

/* BELT TESTS: saved test results and instructor notes; history is retained. */
IF OBJECT_ID(N'dbo.BeltTest', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.BeltTest (
        TestID         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_BeltTest PRIMARY KEY,
        StudentID      INT NOT NULL,
        TestDate       DATE NOT NULL,
        BeltAttempted  NVARCHAR(40) NOT NULL,
        Score          DECIMAL(5,2) NULL,
        Passed         BIT NOT NULL CONSTRAINT DF_BeltTest_Passed DEFAULT (0),
        InstructorNotes NVARCHAR(MAX) NULL,
        GradedBy       NVARCHAR(100) NOT NULL CONSTRAINT DF_BeltTest_GradedBy DEFAULT (N'Sensei Cardone'),
        IsLocked       BIT NOT NULL CONSTRAINT DF_BeltTest_IsLocked DEFAULT (1),
        CreatedAt      DATETIME2 NOT NULL CONSTRAINT DF_BeltTest_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_BeltTest_Student FOREIGN KEY (StudentID)
            REFERENCES dbo.Student(StudentID) ON DELETE NO ACTION
    );
END;
GO

/* ATTENDANCE: one student's check-in status for a class on a date. */
IF OBJECT_ID(N'dbo.Attendance', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Attendance (
        AttendanceID   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Attendance PRIMARY KEY,
        StudentID      INT NOT NULL,
        -- NULL keeps an attendance record if its class is later removed.
        ClassID        INT NULL,
        AttendanceDate DATE NOT NULL CONSTRAINT DF_Attendance_AttendanceDate DEFAULT (CONVERT(DATE, SYSUTCDATETIME())),
        Status         NVARCHAR(20) NOT NULL CONSTRAINT DF_Attendance_Status DEFAULT (N'Present'),
        LoggedBy       NVARCHAR(60) NOT NULL CONSTRAINT DF_Attendance_LoggedBy DEFAULT (N'School Manager'),
        CONSTRAINT CK_Attendance_Status CHECK (Status IN (N'Present', N'Absent', N'Excused')),
        CONSTRAINT FK_Attendance_Student FOREIGN KEY (StudentID)
            REFERENCES dbo.Student(StudentID) ON DELETE NO ACTION,
        CONSTRAINT FK_Attendance_Class FOREIGN KEY (ClassID)
            REFERENCES dbo.Class(ClassID) ON DELETE NO ACTION
    );
END;
GO

/* SAFETY RULE: a student can have only one current class enrollment at a time.
   This is a filtered unique index: only rows marked current are checked. */
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'UX_Enrollment_OneCurrentClass'
      AND object_id = OBJECT_ID(N'dbo.Enrollment')
)
BEGIN
    CREATE UNIQUE INDEX UX_Enrollment_OneCurrentClass
        ON dbo.Enrollment(StudentID)
        WHERE IsCurrentEnrollment = 1;
END;
GO

/* SAFETY RULE: avoid duplicate attendance marks for the same student/class/day. */
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'UX_Attendance_StudentClassDate'
      AND object_id = OBJECT_ID(N'dbo.Attendance')
)
BEGIN
    CREATE UNIQUE INDEX UX_Attendance_StudentClassDate
        ON dbo.Attendance(StudentID, ClassID, AttendanceDate);
END;
GO
