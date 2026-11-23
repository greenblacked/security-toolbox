import { readFileSync } from 'node:fs';

const expectedSources = ['identity', 'audit'];
const approvedGrant = { actor: 'release-bot', role: 'deploy-reader' };

const [fixturePath] = process.argv.slice(2);
if (process.argv.length !== 3) {
  console.error('Usage: node labs/detection-regression.mjs EVENTS_JSON');
  process.exit(2);
}

try {
  const events = JSON.parse(readFileSync(fixturePath, 'utf8'));
  if (!Array.isArray(events)) throw new Error('expected an array of events');
  const sources = new Set();
  const alerts = [];
  for (const event of events) {
    if (!event || ![event.source, event.action, event.actor, event.role].every(
      value => typeof value === 'string' && value.length > 0
    ) || !Number.isFinite(Date.parse(event.timestamp))) {
      throw new Error('invalid event fields');
    }
    sources.add(event.source);
    if (event.source === 'audit' && event.action === 'role.granted'
      && (event.actor !== approvedGrant.actor || event.role !== approvedGrant.role)) {
      alerts.push({ rule: 'unexpected-role-grant', actor: event.actor, role: event.role });
    }
  }
  const missingSources = expectedSources.filter(source => !sources.has(source));
  console.log(JSON.stringify({ alerts, missingSources }, null, 2));
} catch (error) {
  console.error(`Unable to evaluate fixture: ${error.message}`);
  process.exitCode = 2;
}
