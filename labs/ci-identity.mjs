import { readFileSync } from 'node:fs';

const { policies, cases } = JSON.parse(readFileSync(new URL('./fixtures/ci-identity.json', import.meta.url), 'utf8'));

for (const { name, provider, claims } of cases) {
  const policy = Object.hasOwn(policies, provider) ? policies[provider] : {};
  const required = Object.entries(policy);
  const mismatches = required.filter(([key, value]) => !Object.hasOwn(claims, key) || claims[key] !== value);
  const allowed = required.length > 0 && mismatches.length === 0;
  console.log(JSON.stringify({ name, allowed, mismatches: mismatches.map(([key]) => key) }));
}
