import type { ZudokuConfig } from "zudoku";

const config: ZudokuConfig = {
  metadata: {
    title: "BaaS mTLS Platform",
  },
  site: {
    title: "BaaS mTLS Platform",
  },
  navigation: [
    {
      type: "category",
      label: "Documentation",
      items: [
        { type: "doc", label: "Getting Started", file: "pages/getting-started" },
        { type: "doc", label: "Certificate Guide", file: "pages/certificate-guide" },
      ],
    },
    {
      type: "link",
      label: "API Reference",
      to: "/api-reference",
    },
  ],
  apis: [
    {
      type: "file",
      input: "../config/routes.oas.json",
      path: "/api-reference",
    },
  ],
  apiKeys: {
    enabled: true,
  },
};

export default config;
