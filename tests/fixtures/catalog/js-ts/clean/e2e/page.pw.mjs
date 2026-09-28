import { expect, test } from "@playwright/test";

test("renders the heading", async ({ page }) => {
  await page.setContent("<h1>3</h1>");
  await expect(page.locator("h1")).toHaveText("3");
});
