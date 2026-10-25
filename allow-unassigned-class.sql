/*
    ALLOW STUDENTS AND ATTENDANCE TO HAVE NO CLASS
    =============================================

    Run this once against the existing Azure SQL school database.
    The app only connects to the cloud database; it does not run schema changes.

    This makes Enrollment.ClassID and Attendance.ClassID optional. The foreign
    keys remain in place and still use ON DELETE NO ACTION. When a class is
    deleted in the app, its past enrollment and attendance rows are kept with
    ClassID set to NULL. Students currently assigned to the class must first
    be edited and set to "No class".
*/

IF OBJECT_ID(N'dbo.Enrollment', N'U') IS NULL
    THROW 50001, 'dbo.Enrollment was not found. Connect to the school database and try again.', 1;
GO

IF OBJECT_ID(N'dbo.Attendance', N'U') IS NULL
    THROW 50002, 'dbo.Attendance was not found. Connect to the school database and try again.', 1;
GO

DECLARE @EnrollmentClassFK sysname;
DECLARE @EnrollmentDropSQL nvarchar(max);
SELECT TOP (1) @EnrollmentClassFK = name
FROM sys.foreign_keys
WHERE parent_object_id = OBJECT_ID(N'dbo.Enrollment')
  AND referenced_object_id = OBJECT_ID(N'dbo.Class');
IF @EnrollmentClassFK IS NOT NULL
BEGIN
    SET @EnrollmentDropSQL = N'ALTER TABLE dbo.Enrollment DROP CONSTRAINT ' + QUOTENAME(@EnrollmentClassFK);
    EXEC sys.sp_executesql @EnrollmentDropSQL;
END;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(N'dbo.Enrollment') AND name = N'ClassID' AND is_nullable = 0
)
    ALTER TABLE dbo.Enrollment ALTER COLUMN ClassID INT NULL;
GO

ALTER TABLE dbo.Enrollment
    ADD CONSTRAINT FK_Enrollment_Class
    FOREIGN KEY (ClassID) REFERENCES dbo.Class(ClassID) ON DELETE NO ACTION;
GO

DECLARE @AttendanceClassFK sysname;
DECLARE @AttendanceDropSQL nvarchar(max);
SELECT TOP (1) @AttendanceClassFK = name
FROM sys.foreign_keys
WHERE parent_object_id = OBJECT_ID(N'dbo.Attendance')
  AND referenced_object_id = OBJECT_ID(N'dbo.Class');
IF @AttendanceClassFK IS NOT NULL
BEGIN
    SET @AttendanceDropSQL = N'ALTER TABLE dbo.Attendance DROP CONSTRAINT ' + QUOTENAME(@AttendanceClassFK);
    EXEC sys.sp_executesql @AttendanceDropSQL;
END;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(N'dbo.Attendance') AND name = N'ClassID' AND is_nullable = 0
)
    ALTER TABLE dbo.Attendance ALTER COLUMN ClassID INT NULL;
GO

ALTER TABLE dbo.Attendance
    ADD CONSTRAINT FK_Attendance_Class
    FOREIGN KEY (ClassID) REFERENCES dbo.Class(ClassID) ON DELETE NO ACTION;
GO

PRINT 'Class assignments are now optional. Existing class records were kept.';
GO
