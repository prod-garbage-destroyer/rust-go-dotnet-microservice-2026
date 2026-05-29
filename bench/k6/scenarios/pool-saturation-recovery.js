import http from "k6/http";
import { check } from "k6";

const baseUrl = __ENV.BASE_URL || "http://localhost:3001";
const ids = (__ENV.BENCH_USER_IDS || "00000000-0000-0000-0000-000000000001")
  .split(",")
  .map((s) => s.trim())
  .filter((s) => s.length > 0);

if (ids.length === 0) {
  throw new Error("BENCH_USER_IDS must contain at least one UUID");
}

http.setResponseCallback(http.expectedStatuses(200, 404));

function s(n) {
  return `${n}s`;
}

const sustain = Number(__ENV.SATURATION_HOLD_SECONDS || 60);
const recover = Number(__ENV.RECOVERY_OBSERVE_SECONDS || 60);

export const options = {
  discardResponseBodies: true,
  scenarios: {
    pool_saturation_recovery: {
      executor: "ramping-vus",
      startVUs: Number(__ENV.START_VUS || 10),
      stages: [
        { target: Number(__ENV.C1 || 50), duration: s(sustain) },
        { target: Number(__ENV.C2 || 100), duration: s(sustain) },
        { target: Number(__ENV.C3 || 200), duration: s(sustain) },
        { target: Number(__ENV.C4 || 400), duration: s(sustain) },
        { target: Number(__ENV.C5 || 800), duration: s(sustain) },
        { target: Number(__ENV.RECOVERY_VUS || 50), duration: s(recover) }
      ]
    }
  },
  thresholds: {
    http_req_failed: ["rate<0.15"],
    http_req_duration: ["p(99)<1500"]
  },
  summaryTrendStats: ["avg", "med", "max", "p(95)", "p(99)", "p(99.9)"]
};

function randomUserId() {
  const idx = Math.floor(Math.random() * ids.length);
  return ids[idx];
}

export default function () {
  const userId = randomUserId();
  const res = http.get(`${baseUrl}/users/${userId}`);
  check(res, {
    "status is 200 or 404": (r) => r.status === 200 || r.status === 404
  });
}
