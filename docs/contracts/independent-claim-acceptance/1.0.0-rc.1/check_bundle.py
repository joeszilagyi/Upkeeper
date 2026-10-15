#!/usr/bin/env python3
"""Validate the authored package and finite normalized model, not Upkeeper itself.

No network, GitHub, model, shell execution, credentials, runtime grants or host
permission modifications. Facts in model tests are synthetic truth-table inputs.
They must never substitute for independent observations in a real deployment.
"""
from __future__ import annotations
import copy
import hashlib
import itertools
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent

def unique_pairs(pairs):
    output = {}
    for key, value in pairs:
        if key in output:
            raise ValueError(f'duplicate JSON key: {key}')
        output[key] = value
    return output

def load(name):
    return json.loads((ROOT / name).read_text(encoding='utf-8'),
                      object_pairs_hook=unique_pairs,
                      parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)))

def evaluate(facts, model):
    tri_fields = model['input_domain']['tri_state_fields']
    if set(facts) != set(tri_fields) | {'is_noop'}:
        return 'BLOCKED'
    if any(facts[f] not in ('TRUE','FALSE','UNKNOWN') for f in tri_fields):
        return 'BLOCKED'
    if type(facts['is_noop']) is not bool:
        return 'BLOCKED'
    for rule in model['ordered_rules']:
        condition = rule['condition']
        if 'field' in condition:
            match = facts[condition['field']] == condition['equals']
        elif 'any_not_true' in condition:
            match = any(facts[f] != 'TRUE' for f in condition['any_not_true'])
        elif 'any_not_false' in condition:
            match = any(facts[f] != 'FALSE' for f in condition['any_not_false'])
        else:
            match = condition.get('always') is True
        if match:
            return rule['result']
    raise ValueError('decision table has no matching terminal rule')

def main():
    if not __debug__:
        raise RuntimeError('package verification requires assertions; do not run Python with -O or -OO')
    from jsonschema import Draft202012Validator, FormatChecker
    import importlib.metadata
    spec = load('verification-spec.json')
    spec_schema = load('verification-spec.schema.json')
    records_schema = load('records.schema.json')
    for schema in (spec_schema, records_schema):
        Draft202012Validator.check_schema(schema)
    Draft202012Validator(spec_schema, format_checker=FormatChecker()).validate(spec)
    record_validator = Draft202012Validator(records_schema, format_checker=FormatChecker())
    examples = load('examples.json')
    if examples['status'] != 'SYNTHETIC_NOT_AUTHENTICATED_NOT_OPERATIONAL':
        raise ValueError('examples misrepresented as operational evidence')
    for record in examples['records']:
        record_validator.validate(record)
    if {r['record_type'] for r in examples['records']} != set(spec['record_types']):
        raise ValueError('record type examples are incomplete')
    negative_schema_cases = 0
    for record in examples['records']:
        for key in list(record['body']):
            changed = copy.deepcopy(record); del changed['body'][key]
            assert not record_validator.is_valid(changed), (record['record_type'],key)
            negative_schema_cases += 1
        changed = copy.deepcopy(record); changed['body']['trusted'] = True
        assert not record_validator.is_valid(changed)
        negative_schema_cases += 1
    for raw in ('{"result":"PASS","result":"FAIL"}', '{"value":NaN}'):
        try:
            json.loads(raw, object_pairs_hook=unique_pairs,
                       parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)))
        except ValueError:
            negative_schema_cases += 1
        else:
            raise ValueError('unsafe JSON accepted')
    contract=(ROOT/'CONTRACT.md').read_text()
    headings=re.findall(r'^### (ICV-\d{3}): ([^\n]+)$',contract,re.M)
    assert len(headings)==50 and len(set(k for k,_ in headings))==50
    assert dict(headings)=={r['id']:r['title'] for r in spec['requirements']}
    case_headings=re.findall(r'^## (AC-\d{3}): ([^\n]+)$',(ROOT/'ADVERSARIAL-MATRIX.md').read_text(),re.M)
    assert len(case_headings)==62 and dict(case_headings)=={c['id']:c['title'] for c in spec['adversarial_cases']}
    rids={r['id'] for r in spec['requirements']}
    cids={c['id'] for c in spec['adversarial_cases']}
    for r in spec['requirements']:
        assert r['case_ids'] and set(r['case_ids']) <= cids
        expected={c['id'] for c in spec['adversarial_cases'] if r['id'] in c['requirements']}
        assert set(r['case_ids'])==expected
    assert set().union(*(set(c['requirements']) for c in spec['adversarial_cases']))==rids
    model=spec['normalized_decision_model'];positive=model['known_complete_positive_input']
    for vector in model['test_vectors']:
        actual=evaluate({**positive,**vector['changes']},model)
        assert actual==vector['expected'],(vector['id'],actual,vector['expected'])
    for key in positive:
        missing=dict(positive);del missing[key]
        assert evaluate(missing,model)=='BLOCKED'
    assert evaluate({**positive,'worker_says':'WORK_DONE'},model)=='BLOCKED'
    total=0;accepted=0
    fields=model['input_domain']['tri_state_fields']
    for values in itertools.product(('TRUE','FALSE','UNKNOWN'),repeat=len(fields)):
        f=dict(zip(fields,values))
        for noop in (False,True):
            f['is_noop']=noop
            result=evaluate(f,model);total+=1
            ready=all(f[k]=='TRUE' for k in fields if k not in ('verified_violation','required_unknown')) and f['verified_violation']=='FALSE' and f['required_unknown']=='FALSE'
            if result in ('ACCEPTED','NO_CHANGE_VERIFIED'):
                assert ready
                assert result==('NO_CHANGE_VERIFIED' if noop else 'ACCEPTED')
                accepted+=1
            elif ready:
                raise ValueError('legitimate acceptance rejected by finite model')
    assert accepted==2
    action_checks=0
    for action, extras in spec['action_model']['action_specific_requirements'].items():
        gates=list(dict.fromkeys(spec['action_model']['all_actions_require']+extras))
        assert gates
        values={g:True for g in gates};assert all(values.values());action_checks+=1
        for gate in gates:
            for value in (False,None):
                bad={**values,gate:value}
                assert not all(v is True for v in bad.values())
                action_checks+=1
    template=load('adoption-template.json')
    assert template['template_status']=='PENDING_OWNER_ACTION_NOT_VALID_APPROVAL'
    assert template['manifest_sha256'] is None and template['authorization_evidence_ref'] is None
    manifest=load('MANIFEST.json')
    for row in manifest['files']:
        path=ROOT/row['path']
        assert path.parent==ROOT and path.is_file() and not path.is_symlink()
        data=path.read_bytes()
        assert len(data)==row['bytes'] and hashlib.sha256(data).hexdigest()==row['sha256'],row['path']
    files={p.name for p in ROOT.iterdir() if p.is_file()}
    assert files <= {x['path'] for x in manifest['files']} | set(manifest['excluded_generated_files'])
    for row in manifest['files']:
        content=(ROOT/row['path']).read_text(encoding='utf-8')
        assert '\r' not in content and '\u2014' not in content,row['path']
    report={'status':'PASS_PACKAGE_AND_FINITE_MODEL_ONLY','contract_version':spec['version'],
            'requirements':len(rids),'specified_adversarial_cases':len(cids),
            'decision_vectors':len(model['test_vectors']),'normalized_states_exhaustively_checked':total,
            'accepted_normalized_states':accepted,'synthetic_record_examples':len(examples['records']),
            'negative_schema_and_parse_cases':negative_schema_cases,'action_boolean_gate_checks':action_checks,
            'manifest_files_verified':len(manifest['files']),
            'python_version':sys.version.split()[0], 'jsonschema_version':importlib.metadata.version('jsonschema'),
            'not_established':['owner adoption','actual authority isolation','Upkeeper runtime conformance','real actuator enforcement','business correctness','independent external review'],
            'network_calls':0,'model_calls':0,'upkeeper_runtime_tests_run':0}
    print(json.dumps(report,indent=2))
    return 0

if __name__=='__main__':
    raise SystemExit(main())
