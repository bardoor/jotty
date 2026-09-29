import { StrictMode } from "react";
import { createRoot } from "react-dom/client";

import { App } from "./App";
import { createDesktopConnection } from "./connection";
import "./styles.css";

const connection = createDesktopConnection(window.jotty.websocketUrl);
const root = document.getElementById("root");

if (!root) {
  throw new Error("Jotty root element is missing");
}

createRoot(root).render(
  <StrictMode>
    <App connection={connection} />
  </StrictMode>
);
