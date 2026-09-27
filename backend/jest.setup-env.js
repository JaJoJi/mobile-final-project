// Unit tests must not depend on the machine they run on.
//
// Docker sets HOSTNAME in every container (Jenkins runs jest in one), while
// GitHub runners and Windows dev machines don't export it. Code like
// `process.env.HOSTNAME ?? 'local'` then takes a different branch per
// machine, which moved the global branch-coverage number (37.5% locally /
// on GitHub vs 36.9% in Jenkins) across the jest threshold. Tests that
// care about the instance name set HOSTNAME themselves.
delete process.env.HOSTNAME;
