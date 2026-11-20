alter table public.training_attendance
  drop constraint if exists training_attendance_attendance_status_check;

alter table public.training_attendance
  add constraint training_attendance_attendance_status_check
  check (attendance_status = any (array[
    'present'::text,
    'absent'::text,
    'late'::text,
    'excused'::text,
    'injured'::text
  ]));
