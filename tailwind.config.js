// Only files tracked by git count, so the same commit always produces the
// same src/static/tailwind.css – on every machine, whatever else lies around
// locally (doc/Development.md). A new page counts once it is added to git
// (git add, then restart ./tailwind.sh).
const { execFileSync } = require('child_process');

function trackedFiles() {
  try {
    const out = execFileSync('git', ['ls-files', '--', ':(glob)src/static/*.html', ':(glob)src/static/*.js'], { cwd: __dirname, encoding: 'utf8' });
    const files = out.split('\n').filter((f) => f.length > 0);
    if (files.length > 0) return files;
  } catch (err) {
    // no git (e.g. a copy without .git): fall back to everything
  }
  return ['src/static/*.html', 'src/static/*.js'];
}

module.exports = {
  content: trackedFiles(),
  theme: {},
  plugins: [],
}
