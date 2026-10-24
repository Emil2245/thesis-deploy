import { login, iteration } from './common.js';

export const options = {
  insecureSkipTLSVerify: true,
  scenarios: {
    constant: {
      executor: 'constant-vus',
      vus: Number(__ENV.VUS || 10),
      duration: __ENV.DURATION || '3m',
    },
  },
  thresholds: { http_req_failed: ['rate<0.01'], http_req_duration: ['p(95)<2000'] },
};
export function setup() { return { token: login() }; }
export default function (d) { iteration(d.token); }
