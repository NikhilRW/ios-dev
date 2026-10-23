import { expect, test } from '@jest/globals';
import {
  formatPercentage,
  mentionedSubjects,
  nextAttendance,
  overall,
  parseAction,
  validStoredSubjects,
  type Subject,
} from '../personal/attendanceLogic';

const maths: Subject = { id: '1', name: 'Maths', attended: 3, total: 4 };
const physics: Subject = { id: '2', name: 'Physics', attended: 0, total: 0 };

test('calculates present, absent, combined, and zero-total attendance', () => {
  expect(formatPercentage(0, 0)).toBe('0.0%');
  expect(nextAttendance(maths, 'present')).toMatchObject({ attended: 4, total: 5 });
  expect(nextAttendance(maths, 'absent')).toMatchObject({ attended: 3, total: 5 });
  expect(nextAttendance(maths, 'hypothetical')).toMatchObject({ attended: 3, total: 5 });
  expect(overall([maths, physics])).toEqual({ attended: 3, total: 4 });
  expect(formatPercentage(3, 5)).toBe('60.0%');
});

test('recognizes messages and finds named subjects without guessing', () => {
  expect(parseAction('I missed Maths today')).toBe('absent');
  expect(parseAction('I attended Maths today')).toBe('present');
  expect(parseAction('What if I miss one Maths class?')).toBe('hypothetical');
  expect(mentionedSubjects('I missed Maths today', [maths, physics])).toEqual([maths]);
  expect(mentionedSubjects('I missed Maths and Physics', [maths, physics])).toHaveLength(2);
  expect(mentionedSubjects('I missed class', [maths, physics])).toHaveLength(0);
});

test('rejects invalid stored counts and duplicate subjects', () => {
  expect(validStoredSubjects([maths, { ...maths, id: '3', name: 'maths' },
    { id: '4', name: 'Bad', attended: 5, total: 4 }, physics])).toEqual([maths, physics]);
});
