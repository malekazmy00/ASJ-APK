import assert from "node:assert/strict";
import test from "node:test";
import { sessionIdentity } from "../supabase/functions/_shared/session_identity.ts";

const activeUser = {
  role: "worker",
  status: "Active",
  password_changed_at: null,
};

test("a demoted administrator gets the current database role", () => {
  assert.deepEqual(sessionIdentity("user", 100, activeUser, 200), {
    username: "user",
    role: "worker",
  });
});
test("deleted and suspended accounts cannot retain a signed session", () => {
  assert.equal(sessionIdentity("user", 100, null, 200), null);
  assert.equal(
    sessionIdentity("user", 100, { ...activeUser, status: "Inactive" }, 200),
    null,
  );
});
test("changing a password invalidates sessions issued before the change", () => {
  const user = {
    ...activeUser,
    password_changed_at: "1970-01-01T00:01:41.000Z",
  };
  assert.equal(sessionIdentity("user", 100, user, 200), null);
  assert.ok(sessionIdentity("user", 102, user, 200));
});
test("invalid roles, timestamps, and corrupt revocation dates fail closed", () => {
  assert.equal(
    sessionIdentity("user", 100, { ...activeUser, role: "owner" }, 200),
    null,
  );
  assert.equal(sessionIdentity("user", NaN, activeUser, 200), null);
  assert.equal(sessionIdentity("user", 201, activeUser, 200), null);
  assert.equal(
    sessionIdentity("user", 100, {
      ...activeUser,
      password_changed_at: "invalid",
    }, 200),
    null,
  );
});

