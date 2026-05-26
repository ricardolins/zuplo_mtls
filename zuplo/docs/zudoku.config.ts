import type { ZudokuConfig } from "zudoku";

const config: ZudokuConfig = {
  metadata: {
    title: "BaaS mTLS Platform",
  },
  site: {
    title: "BaaS mTLS Platform",
  },
  docs: {
    files: "/pages/**/*.{md,mdx}",
  },
  navigation: [
    {
      type: "category",
      label: "Documentation",
      items: [
        { type: "link", label: "Getting Started", to: "/getting-started" },
        { type: "link", label: "Certificate Guide", to: "/certificate-guide" },
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
  redirects: [{ from: "/", to: "/api-reference" }],
};

export default config;
