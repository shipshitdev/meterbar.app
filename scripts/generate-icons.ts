#!/usr/bin/env bun

/**
 * Icon Generator for MeterBar
 *
 * Generates service icons and app icons at multiple scales.
 *
 * Usage:
 *   bun run generate-icons.ts
 */

import { chromium } from "playwright";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = resolve(__dirname, "..");

interface ServiceIcon {
	name: string;
	label: string;
	gradient: { from: string; to: string };
	folder: string;
	prefix: string;
}

const SERVICES: ServiceIcon[] = [
	{
		name: "Claude Code",
		label: "CC",
		gradient: { from: "#d97706", to: "#f59e0b" },
		folder: "ClaudeIcon.imageset",
		prefix: "claude",
	},
	{
		name: "OpenAI",
		label: "AI",
		gradient: { from: "#10b981", to: "#34d399" },
		folder: "OpenAIIcon.imageset",
		prefix: "openai",
	},
	{
		name: "Cursor",
		label: "Cu",
		gradient: { from: "#06b6d4", to: "#22d3ee" },
		folder: "CursorIcon.imageset",
		prefix: "cursor",
	},
	{
		name: "Codex",
		label: "Cx",
		gradient: { from: "#8b5cf6", to: "#a78bfa" },
		folder: "CodexIcon.imageset",
		prefix: "codex",
	},
];

const SERVICE_SCALES = [
	{ scale: "1x", size: 24 },
	{ scale: "2x", size: 48 },
	{ scale: "3x", size: 72 },
];

const APP_ICON_SIZES = [16, 32, 128, 256, 512];

function createServiceIconSvg(service: ServiceIcon, size: number): string {
	const fontSize = Math.round(size * 0.45);
	const radius = Math.round(size * 0.25);

	return `
<!DOCTYPE html>
<html>
<head>
  <style>
    @import url('https://fonts.googleapis.com/css2?family=Inter:wght@600&display=swap');
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body {
      width: ${size}px;
      height: ${size}px;
      background: transparent !important;
      overflow: hidden;
    }
    .icon {
      width: ${size}px;
      height: ${size}px;
      border-radius: ${radius}px;
      background: linear-gradient(135deg, ${service.gradient.from} 0%, ${service.gradient.to} 100%);
      display: flex;
      align-items: center;
      justify-content: center;
      font-family: 'Inter', -apple-system, sans-serif;
      font-size: ${fontSize}px;
      font-weight: 600;
      color: white;
      text-shadow: 0 1px 2px rgba(0,0,0,0.2);
    }
  </style>
</head>
<body>
  <div class="icon">${service.label}</div>
</body>
</html>`;
}

function createAppIconSvg(size: number): string {
	const barHeight = Math.round(size * 0.086);
	const barRadius = barHeight / 2;
	const barWidth = Math.round(size * 0.625);
	const margin = Math.round(size * 0.1875);
	const bgRadius = Math.round(size * 0.1875);
	const spacing = Math.round(size * 0.16);

	// Usage levels: low (green), medium (yellow), high (red)
	// Bar fills go from empty to full, colors indicate status
	const bar1Fill = 0.30; // 30% - Green (good)
	const bar2Fill = 0.55; // 55% - Yellow (warning)
	const bar3Fill = 0.85; // 85% - Red (critical)

	const bar1Width = Math.round(barWidth * bar1Fill);
	const bar2Width = Math.round(barWidth * bar2Fill);
	const bar3Width = Math.round(barWidth * bar3Fill);

	const y1 = Math.round(size * 0.297);
	const y2 = y1 + spacing;
	const y3 = y2 + spacing;

	return `
<!DOCTYPE html>
<html>
<head>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body {
      width: ${size}px;
      height: ${size}px;
      background: #0f0f1a !important;
      overflow: hidden;
    }
  </style>
</head>
<body>
  <svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" xmlns="http://www.w3.org/2000/svg">
    <defs>
      <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stop-color="#1a1a2e"/>
        <stop offset="100%" stop-color="#0f0f1a"/>
      </linearGradient>
      <linearGradient id="barGreen" x1="0%" y1="0%" x2="100%" y2="0%">
        <stop offset="0%" stop-color="#22c55e"/>
        <stop offset="100%" stop-color="#4ade80"/>
      </linearGradient>
      <linearGradient id="barYellow" x1="0%" y1="0%" x2="100%" y2="0%">
        <stop offset="0%" stop-color="#f59e0b"/>
        <stop offset="100%" stop-color="#fbbf24"/>
      </linearGradient>
      <linearGradient id="barRed" x1="0%" y1="0%" x2="100%" y2="0%">
        <stop offset="0%" stop-color="#ef4444"/>
        <stop offset="100%" stop-color="#f87171"/>
      </linearGradient>
    </defs>
    <!-- Full background fill -->
    <rect x="0" y="0" width="${size}" height="${size}" fill="url(#bg)"/>
    <!-- Bar 1: Low usage (Green) -->
    <rect x="${margin}" y="${y1}" width="${barWidth}" height="${barHeight}" rx="${barRadius}" fill="#2a2a4a"/>
    <rect x="${margin}" y="${y1}" width="${bar1Width}" height="${barHeight}" rx="${barRadius}" fill="url(#barGreen)"/>
    <!-- Bar 2: Medium usage (Yellow) -->
    <rect x="${margin}" y="${y2}" width="${barWidth}" height="${barHeight}" rx="${barRadius}" fill="#2a2a4a"/>
    <rect x="${margin}" y="${y2}" width="${bar2Width}" height="${barHeight}" rx="${barRadius}" fill="url(#barYellow)"/>
    <!-- Bar 3: High usage (Red) -->
    <rect x="${margin}" y="${y3}" width="${barWidth}" height="${barHeight}" rx="${barRadius}" fill="#2a2a4a"/>
    <rect x="${margin}" y="${y3}" width="${bar3Width}" height="${barHeight}" rx="${barRadius}" fill="url(#barRed)"/>
  </svg>
</body>
</html>`;
}

async function generateIcons(): Promise<void> {
	console.log("🎨 Generating icons...\n");

	const browser = await chromium.launch({ headless: true });

	// Generate service icons
	console.log("📦 Generating service icons...");
	for (const service of SERVICES) {
		const folder = resolve(
			ROOT_DIR,
			"MeterBarWidget/Assets.xcassets",
			service.folder
		);

		for (const { scale, size } of SERVICE_SCALES) {
			const html = createServiceIconSvg(service, size);
			const page = await browser.newPage();
			await page.setViewportSize({ width: size, height: size });
			await page.setContent(html, { waitUntil: "networkidle" });
			await page.waitForTimeout(500);

			const outputPath = resolve(folder, `${service.prefix}@${scale}.png`);
			await page.screenshot({
				path: outputPath,
				type: "png",
				omitBackground: true,
			});
			await page.close();
			console.log(`  ✓ ${service.name} @${scale}`);
		}
	}

	// Generate app icons
	console.log("\n📱 Generating app icons...");
	const appIconFolders = [
		resolve(ROOT_DIR, "MeterBar/Assets.xcassets/AppIcon.appiconset"),
		resolve(ROOT_DIR, "MeterBarWidget/Assets.xcassets/AppIcon.appiconset"),
	];

	for (const folder of appIconFolders) {
		const folderName = folder.includes("MeterBarWidget") ? "Widget" : "Main";
		console.log(`  ${folderName} app icon:`);

		for (const size of APP_ICON_SIZES) {
			for (const multiplier of [1, 2]) {
				const actualSize = size * multiplier;
				const suffix = multiplier === 1 ? "" : "@2x";
				const filename = `icon_${size}x${size}${suffix}.png`;

				const html = createAppIconSvg(actualSize);
				const page = await browser.newPage();
				await page.setViewportSize({ width: actualSize, height: actualSize });
				await page.setContent(html, { waitUntil: "networkidle" });

				const outputPath = resolve(folder, filename);
				// App icons should NOT have transparent background for macOS
				await page.screenshot({ path: outputPath, type: "png" });
				await page.close();
				console.log(`    ✓ ${filename}`);
			}
		}
	}

	await browser.close();
	console.log("\n🎉 All icons generated!");
}

generateIcons().catch((error) => {
	console.error("❌ Failed:", error);
	process.exit(1);
});
