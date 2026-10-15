"""Exercise the validator's actual existential filters on the installed jq.

No fake JSON tool: extract only the two literal argument arrays, never eval
shell source. Full validation separately executes the complete real entrypoint.
"""
import json
from pathlib import Path
import re
import subprocess
import tempfile

source = Path(__file__).resolve().parents[2]
text = (source/'tools/validate_upkeeper.sh').read_text()
body = text.split('check_prior_run_anomaly_custody_contract() {', 1)[1].split('\n}', 1)[0]
filters = re.findall(r"^  jq (-e(?: -s)?) '([^']+)' \\", body, re.M)
filters = [pair for pair in filters if 'specific_issue_required' in pair[1] or 'issue_title_basis' in pair[1]]
assert len(filters) == 2, 'expected two real existential checks'
root = Path(tempfile.mkdtemp(prefix='validator-json-exit-'))
match = {
    'kind': 'prior_run_anomaly', 'issue_number': '', 'owner_issue_number': '418',
    'specific_issue_required': True,
    'evidence': {'normalized_excerpt': 'unexpected.wrapper.failure operator_guide.stale'},
    'summary': 'operator_guide.stale warning',
    'issue_title': 'High priority bug: prior-run operator_guide.stale warning needs repair for Upkeeper',
    'issue_title_basis': 'prior_run_anomaly_signal',
}
other = {**match, 'kind': 'unrelated', 'issue_title_basis': 'unrelated'}
for name, value in [('match', match), ('other', other)]:
    (root/name).write_text(json.dumps(value))
(root/'malformed').write_text('{bad')
print('validator JSON exit conditions: '+subprocess.check_output(['jq', '--version'], text=True).strip())
for index, (flags, predicate) in enumerate(filters):
    def run(names):
        result = subprocess.run(['jq', *flags.split(), predicate, *[str(root/n) for n in names]],
                                text=True, capture_output=True, timeout=5)
        (root/f'result-{index}-{len(list(root.iterdir()))}.json').write_text(json.dumps({
            'names': names, 'exit': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr}))
        return result.returncode
    for names in (['match', 'other'], ['other', 'match'], ['match']):
        assert run(names) == 0, ('matching record must pass in either order', index, names, root)
    assert run(['other']) != 0, ('absent match passed', index, root)
    assert run(['match', 'malformed']) != 0, ('malformed input passed', index, root)
    # Every original predicate remains necessary; a partial record is no proof.
    fields = (('kind', 'issue_number', 'owner_issue_number', 'specific_issue_required', 'evidence')
              if index == 0 else ('evidence', 'summary', 'issue_title', 'issue_title_basis'))
    for field in fields:
        damaged = dict(match)
        damaged[field] = {'normalized_excerpt': 'unrelated'} if field == 'evidence' else 'wrong'
        (root/'damaged').write_text(json.dumps(damaged))
        assert run(['damaged', 'other']) != 0, ('predicate was weakened', index, field, root)
print('validator JSON exit conditions: passed both orders, absent/malformed/partial records')

# Inject only the search transport status into the actual production guard.
# Other focused tests are stubbed here; full validation executes them normally.
guard = text.split('check_wrapper_contract_tests() {', 1)[1].split('\n}', 1)[0]
driver = '''set -eu
_test_rg_rc="$1"
log() { :; }
validation_run_test() { :; }
rg() { return "$_test_rg_rc"; }
fail() { printf '%s\\n' "$*" >&2; exit 1; }
check_wrapper_contract_tests() {\n''' + guard + '\n}\ncheck_wrapper_contract_tests\n'
for status, expected in ((0, 1), (1, 0), (2, 1), (127, 1)):
    result = subprocess.run(['bash', '-c', driver, 'guard-probe', str(status)],
                            cwd=source, text=True, capture_output=True, timeout=5)
    (root/f'rg-status-{status}.json').write_text(json.dumps({
        'injected_status': status, 'exit': result.returncode, 'stderr': result.stderr}))
    assert result.returncode == expected, ('search error mistaken for no match', status, result, root)
print('validator search exit conditions: match rejected, no-match accepted, errors blocked')
