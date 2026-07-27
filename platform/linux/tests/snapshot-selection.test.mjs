import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';

const fixtureUrl = new URL('../fixtures/dayman-state-v1.json', import.meta.url);
const state = JSON.parse(await readFile(fixtureUrl, 'utf8'));

function selectSnapshotForDate(envelope, currentDateKey) {
  const fallback = envelope?.snapshot;
  if (fallback?.schemaVersion !== 1)
    return null;

  const queue = Array.isArray(envelope.snapshots) ? envelope.snapshots : [];
  if (queue.length > 0) {
    return queue.find(candidate =>
      candidate?.schemaVersion === 1 &&
      candidate.timezone === fallback.timezone &&
      candidate.dateKey === currentDateKey
    ) ?? null;
  }
  return fallback.dateKey === currentDateKey ? fallback : null;
}

test('selects the queued snapshot matching the saved-zone date', () => {
  assert.equal(selectSnapshotForDate(state, '2026-07-27')?.dateKey, '2026-07-27');
});

test('does not use a stale fallback when a non-empty queue has no match', () => {
  assert.equal(selectSnapshotForDate(state, '2026-08-30'), null);
});

test('uses a legacy singular snapshot only when it is current', () => {
  const legacy = {...state, snapshots: []};
  assert.equal(selectSnapshotForDate(legacy, '2026-07-26'), state.snapshot);
  assert.equal(selectSnapshotForDate(legacy, '2026-07-27'), null);
});

test('treats a missing queue like legacy state', () => {
  const {snapshots: _snapshots, ...legacy} = state;
  assert.equal(selectSnapshotForDate(legacy, '2026-07-26'), state.snapshot);
  assert.equal(selectSnapshotForDate(legacy, '2026-07-25'), null);
});
