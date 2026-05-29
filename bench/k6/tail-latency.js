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

export const options = {
  discardResponseBodies: true,
  scenarios: {
    tail_open_loop: {
      executor: "ramping-arrival-rate",
      timeUnit: "1s",
      preAllocatedVUs: Number(__ENV.PREALLOCATED_VUS || 300),
      maxVUs: Number(__ENV.MAX_VUS || 3000),
      startRate: Number(__ENV.START_RATE || 2000),
      stages: [
        { target: Number(__ENV.STAGE1_RPS || 2000), duration: __ENV.STAGE_DURATION || "90s" },
        { target: Number(__ENV.STAGE2_RPS || 5000), duration: __ENV.STAGE_DURATION || "90s" },
        { target: Number(__ENV.STAGE3_RPS || 10000), duration: __ENV.STAGE_DURATION || "90s" },
        { target: Number(__ENV.STAGE4_RPS || 15000), duration: __ENV.STAGE_DURATION || "90s" },
        { target: Number(__ENV.STAGE5_RPS || 20000), duration: __ENV.STAGE_DURATION || "90s" }
      ]
    }
  },
  thresholds: {
    http_req_failed: ["rate<0.05"],
    http_req_duration: ["p(95)<250", "p(99)<500", "p(99.9)<1000"]
  },
  summaryTrendStats: ["avg", "min", "med", "max", "p(90)", "p(95)", "p(99)", "p(99.9)"]
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
