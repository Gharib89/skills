const { add } = require("./mathjs");

test("adds", () => {
  expect(add(1, 2)).toBe(3);
});
