-- =========================================================================
-- Shodan Karate Martial Arts Studio - Azure SQL Schema
-- Database: Karate-School
-- Owner: Tristan Cardone (Sensei Cardone)
-- =========================================================================

-- Parents / Guardian info & billing
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Parent')
CREATE TABLE Parent (
    ParentID INT IDENTITY(1,1) PRIMARY KEY,
    FirstName NVARCHAR(60) NOT NULL,
    LastName NVARCHAR(60) NOT NULL,
    Phone NVARCHAR(20) NOT NULL,
    Email NVARCHAR(120) NOT NULL,
    Address NVARCHAR(200) NOT NULL,
    City NVARCHAR(60) NOT NULL,
    State NVARCHAR(30) NOT NULL,
    ZipCode NVARCHAR(10) NOT NULL,
    BillingMethod NVARCHAR(30) NOT NULL DEFAULT 'Monthly',
    MonthlyRate DECIMAL(8,2) NOT NULL DEFAULT 80.00,
    CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME()
);
GO

-- Students
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Student')
CREATE TABLE Student (
    StudentID INT IDENTITY(1,1) PRIMARY KEY,
    FirstName NVARCHAR(60) NOT NULL,
    LastName NVARCHAR(60) NOT NULL,
    DateOfBirth DATE NOT NULL,
    BeltRank NVARCHAR(40) NOT NULL DEFAULT 'White',
    EnrollmentDate DATE NOT NULL DEFAULT CAST(SYSUTCDATETIME() AS DATE),
    IsActive BIT NOT NULL DEFAULT 1,
    BlackBeltWaitingStart DATE NULL,
    IsInBlackBeltTesting BIT NOT NULL DEFAULT 0,
    Notes NVARCHAR(MAX) NULL,
    CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME()
);
GO

-- Link students to parents (a student can have 1 or 2 parents)
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'StudentParent')
CREATE TABLE StudentParent (
    StudentID INT NOT NULL,
    ParentID INT NOT NULL,
    Relationship NVARCHAR(30) NOT NULL DEFAULT 'Parent',
    IsPrimaryContact BIT NOT NULL DEFAULT 1,
    PRIMARY KEY (StudentID, ParentID),
    FOREIGN KEY (StudentID) REFERENCES Student(StudentID) ON DELETE NO ACTION,
    FOREIGN KEY (ParentID) REFERENCES Parent(ParentID) ON DELETE NO ACTION
);
GO

-- Classes
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Class')
CREATE TABLE Class (
    ClassID INT IDENTITY(1,1) PRIMARY KEY,
    ClassName NVARCHAR(80) NOT NULL,
    AgeGroupMin INT NOT NULL,
    AgeGroupMax INT NOT NULL,
    Schedule NVARCHAR(100) NOT NULL,
    InstructorName NVARCHAR(100) NOT NULL DEFAULT 'Sensei Cardone',
    MaxCapacity INT NOT NULL DEFAULT 20,
    IsActive BIT NOT NULL DEFAULT 1
);
GO

-- Enrollment: student belongs to ONE class at a time
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Enrollment')
CREATE TABLE Enrollment (
    EnrollmentID INT IDENTITY(1,1) PRIMARY KEY,
    StudentID INT NOT NULL,
    ClassID INT NULL,
    EnrolledDate DATE NOT NULL DEFAULT CAST(SYSUTCDATETIME() AS DATE),
    IsCurrentEnrollment BIT NOT NULL DEFAULT 1,
    FOREIGN KEY (StudentID) REFERENCES Student(StudentID) ON DELETE NO ACTION,
    FOREIGN KEY (ClassID) REFERENCES Class(ClassID) ON DELETE NO ACTION
);
GO

-- Belt test records (locked - cannot be deleted)
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'BeltTest')
CREATE TABLE BeltTest (
    TestID INT IDENTITY(1,1) PRIMARY KEY,
    StudentID INT NOT NULL,
    TestDate DATE NOT NULL,
    BeltAttempted NVARCHAR(40) NOT NULL,
    Score DECIMAL(5,2) NULL,
    Passed BIT NOT NULL DEFAULT 0,
    InstructorNotes NVARCHAR(MAX) NULL,
    GradedBy NVARCHAR(100) NOT NULL DEFAULT 'Sensei Cardone',
    IsLocked BIT NOT NULL DEFAULT 1,
    CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME(),
    FOREIGN KEY (StudentID) REFERENCES Student(StudentID) ON DELETE NO ACTION
);
GO

-- Attendance log
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Attendance')
CREATE TABLE Attendance (
    AttendanceID INT IDENTITY(1,1) PRIMARY KEY,
    StudentID INT NOT NULL,
    ClassID INT NULL,
    AttendanceDate DATE NOT NULL DEFAULT CAST(SYSUTCDATETIME() AS DATE),
    Status NVARCHAR(20) NOT NULL DEFAULT 'Present',
    LoggedBy NVARCHAR(60) NOT NULL DEFAULT 'System',
    FOREIGN KEY (StudentID) REFERENCES Student(StudentID) ON DELETE NO ACTION,
    FOREIGN KEY (ClassID) REFERENCES Class(ClassID) ON DELETE NO ACTION
);
GO

-- Seed Classes (only if table is empty)
IF NOT EXISTS (SELECT * FROM Class)
BEGIN
    INSERT INTO Class (ClassName, AgeGroupMin, AgeGroupMax, Schedule, InstructorName, MaxCapacity, IsActive)
    VALUES
        ('Little Ninjas',  4,  6, 'Mon/Wed 4:00 PM',       'Sensei Cardone', 15, 1),
        ('Youth Class',    7, 13, 'Tue/Thu 5:00 PM',       'Sensei Cardone', 20, 1),
        ('Adult Class',   13, 99, 'Mon/Wed/Fri 6:00 PM',   'Sensei Cardone', 25, 1),
        ('Kickboxing',    18, 99, 'Tue/Thu 7:00 PM',       'Sensei Cardone', 20, 1);
END
GO

-- One current class per student, and at most one attendance mark per class/date.
-- The app and database both preserve the school's one-class-at-a-time rule.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Enrollment_OneCurrentClass' AND object_id = OBJECT_ID('dbo.Enrollment'))
    CREATE UNIQUE INDEX UX_Enrollment_OneCurrentClass ON dbo.Enrollment(StudentID) WHERE IsCurrentEnrollment = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Attendance_StudentClassDate' AND object_id = OBJECT_ID('dbo.Attendance'))
    CREATE UNIQUE INDEX UX_Attendance_StudentClassDate ON dbo.Attendance(StudentID, ClassID, AttendanceDate);
GO
