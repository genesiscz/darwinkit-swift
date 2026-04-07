import { DarwinKit } from "./packages/darwinkit/src/index.js";

const dk = new DarwinKit({
  binary: "./packages/darwinkit/bin/DarwinKit.app/Contents/MacOS/darwinkit",
  timeout: 10_000,
});

await dk.connect();
console.log("Connected to DarwinKit");

// Listen for interaction callbacks
dk.notifications.onInteraction((event) => {
  console.log("\n--- Interaction received! ---");
  console.log("Action:", event.action_identifier);
  console.log("Notification:", event.notification_identifier);
  console.log("Category:", event.category_identifier);
  if (event.user_text) {
    console.log("User text:", event.user_text);
  }
  console.log("User info:", event.user_info);
  console.log("----------------------------\n");

  // Clean up and exit
  dk.close();
  process.exit(0);
});

// Register category with reply action
await dk.notifications.registerCategory({
  identifier: "TEST_REPLY",
  actions: [
    {
      identifier: "REPLY",
      title: "Reply",
      text_input: true,
      text_input_button_title: "Send",
      text_input_placeholder: "Type something...",
    },
    { identifier: "LIKE", title: "Like" },
    { identifier: "DISMISS", title: "Dismiss", destructive: true },
  ],
});
console.log("Category registered");

// Send notification
const result = await dk.notifications.send({
  title: "DarwinKit Test",
  body: "Reply to this notification and see the callback!",
  subtitle: "Interactive test",
  sound: "default",
  category_identifier: "TEST_REPLY",
  user_info: { test: true, timestamp: Date.now() },
});
console.log("Notification sent:", result.identifier);
console.log("\nWaiting for you to interact with the notification...");
