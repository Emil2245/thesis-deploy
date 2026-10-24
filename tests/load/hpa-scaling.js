import { login, iteration } from './common.js';

const MULT = Number(__ENV.VU_MULT || 1);
export const options = {
  insecureSkipTLSVerify: true,
  scenarios: {
    ramp: {
      executor: 'ramping-vus',
      stages: [
        { duration: '2m', target: 20 * MULT },
        { duration: '5m', target: 50 * MULT },
        { duration: '2m', target: 0 },
      ],
    },
  },
  thresholds: { http_req_failed: ['rate<0.01'], http_req_duration: ['p(95)<2000'] },
};
export function setup() { return { token: login() }; }
export default function (d) { iteration(d.token); }
