const platformMatchers = {
  ios: [
    /^ios\b/i,
    /\bios\b/i,
    /\bxcode\b/i,
    /\bxcconfig\b/i,
    /settings\.bundle/i
  ],
  android: [
    /^android\b/i,
    /\bandroid\b/i,
    /\bgradle\b/i
  ]
};

function targetArtifactsForPlatform(targetArtifacts, platform, variantId = "") {
  const artifacts = Array.isArray(targetArtifacts)
    ? targetArtifacts.filter((artifact) => typeof artifact === "string" && artifact.trim().length > 0)
    : [];

  if (platform === "cross-platform") {
    return artifacts.map((artifact) => artifact.replaceAll("<variant>", variantId || "<variant>"));
  }

  const ownMatchers = platformMatchers[platform] || [];
  const otherPlatforms = Object.keys(platformMatchers).filter((candidate) => candidate !== platform);
  const otherMatchers = otherPlatforms.flatMap((candidate) => platformMatchers[candidate]);

  return artifacts
    .filter((artifact) => {
      if (ownMatchers.some((matcher) => matcher.test(artifact))) {
        return true;
      }
      return !otherMatchers.some((matcher) => matcher.test(artifact));
    })
    .map((artifact) => artifact.replaceAll("<variant>", variantId || "<variant>"));
}

function answerFieldsForPlatform(answerFields, platform) {
  const fields = Array.isArray(answerFields)
    ? answerFields.filter((field) => field && typeof field === "object" && typeof field.id === "string" && field.id.trim().length > 0)
    : [];

  if (platform === "cross-platform") {
    return fields;
  }

  return fields.filter((field) => {
    if (!Array.isArray(field.platforms) || field.platforms.length === 0) {
      return true;
    }
    return field.platforms.includes(platform);
  });
}

function decisionChecklistForPlatform(catalog, requiredDecisionIds, platform, variantId = "") {
  return requiredDecisionIds.map((decisionId) => {
    const decision = catalog[decisionId] || {};
    return {
      id: decisionId,
      status: "needed",
      question: decision.question,
      targetArtifacts: targetArtifactsForPlatform(decision.targetArtifacts, platform, variantId),
      answerFields: answerFieldsForPlatform(decision.answerFields, platform)
    };
  });
}

module.exports = {
  answerFieldsForPlatform,
  decisionChecklistForPlatform,
  targetArtifactsForPlatform
};
