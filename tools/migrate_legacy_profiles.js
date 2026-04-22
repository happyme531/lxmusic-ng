#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const LEGACY_ROOT = '/home/zt/clxTools/楚留香音乐盒/src';

const GameProfileCtor = require(path.join(LEGACY_ROOT, 'gameProfile.js'));
const midiPitch = require(path.join(LEGACY_ROOT, 'midiPitch.js'));

function main() {
  const outputProfilesDir = path.join(ROOT, 'assets', 'game_profiles');
  const outputLayoutsDir = path.join(ROOT, 'assets', 'layouts');

  fs.mkdirSync(outputProfilesDir, { recursive: true });
  fs.mkdirSync(outputLayoutsDir, { recursive: true });

  const gameProfile = new GameProfileCtor();
  gameProfile.loadDefaultGameConfigs();
  const configs = gameProfile.getGameConfigs();

  const layoutMap = new Map();
  let profileCount = 0;

  for (const config of configs) {
    for (const keyType of config.keyTypes) {
      layoutMap.set(keyType.name, keyType.keyLayout);
    }

    const profileId = inferProfileId(config, profileCount);
    const outputPath = path.join(outputProfilesDir, `${profileId}.yaml`);
    const profileDoc = {
      id: profileId,
      displayName: config.gameName,
      packageNameHints: config.packageNamePart || [],
      defaultLayoutId: config.keyTypes[0]?.name || null,
      sameKeyMinIntervalMs: config.sameKeyMinInterval || 20,
      featureFlags: [],
      layouts: config.keyTypes.map((item, index) => ({
        layoutId: item.name,
        displayName: item.displayName,
        isDefault: index === 0,
      })),
      variants: buildVariants(config.variants || []),
    };

    fs.writeFileSync(outputPath, serializeJsonAsYaml(profileDoc));
    profileCount++;
  }

  let layoutCount = 0;
  for (const [layoutId, params] of layoutMap.entries()) {
    const outputPath = path.join(outputLayoutsDir, `${layoutId}.yaml`);
    const layoutDoc = {
      id: layoutId,
      algorithm: 'procedural',
      metadata: {
        importedFrom: 'legacy_gameProfile.js',
      },
      params,
    };
    fs.writeFileSync(outputPath, serializeJsonAsYaml(layoutDoc));
    layoutCount++;
  }

  console.log(
    `[migrate_legacy_profiles] wrote ${profileCount} profiles and ${layoutCount} layouts`,
  );
}

function inferProfileId(config, index) {
  const packageHints = config.packageNamePart || [];
  for (const hint of packageHints) {
    const slug = String(hint).toLowerCase().replace(/[^a-z0-9]+/g, '_');
    if (slug) {
      return slug;
    }
  }
  return `legacy_${String(index + 1).padStart(2, '0')}`;
}

function normalizeVariantId(raw) {
  return String(raw)
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

function normalizeDurationMode(raw) {
  if (raw === 'native') {
    return 'nativeHold';
  }
  if (raw === 'extraLongKey') {
    return 'extraLongKey';
  }
  return 'none';
}

function serializeJsonAsYaml(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

function buildVariants(variants) {
  const usedIds = new Set();
  return variants.map((variant, index) => {
    const rawId = variant.variantType || variant.variantName || 'default';
    let id = normalizeVariantId(rawId);
    if (!id) {
      id = rawId === 'default' || index === 0 ? 'default' : `variant_${index + 1}`;
    }
    while (usedIds.has(id)) {
      id = `${id}_${index + 1}`;
    }
    usedIds.add(id);
    return {
      id,
      displayName: variant.variantName || variant.variantType || '默认',
      noteDurationMode: normalizeDurationMode(
        variant.noteDurationImplementionType || 'none',
      ),
      availablePitchRange: variant.availableNoteRange
        ? [
            midiPitch.nameToMidiPitch(variant.availableNoteRange[0]),
            midiPitch.nameToMidiPitch(variant.availableNoteRange[1]),
          ]
        : null,
      replacePitchMap: variant.replaceNoteMap
        ? Object.fromEntries(
            Object.entries(variant.replaceNoteMap).map(([from, to]) => [
              midiPitch.nameToMidiPitch(from),
              midiPitch.nameToMidiPitch(to),
            ]),
          )
        : {},
      sameKeyMinIntervalOverrideMs: variant.sameKeyMinInterval ?? null,
    };
  });
}

main();
