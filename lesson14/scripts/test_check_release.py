"""Run the real release checker against command stubs; no AWS or HTTP requests."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


CHECKER = Path(__file__).with_name("check-release.sh")
SERVICES = ["user", "product", "cart", "order", "payment", "notification"]
CLOUDFRONT = "https://d111111abcdef8.cloudfront.net"
API = "https://abc123defg.execute-api.ap-southeast-1.amazonaws.com"
STUB = r'''
import json, os, sys
from pathlib import Path

tool = Path(sys.argv[0]).name
args = sys.argv[1:]
scenario = os.environ['CHECK_SCENARIO']
with open(os.environ['CHECK_CALLS'], 'a') as log:
    log.write(json.dumps([tool, args]) + '\n')

SERVICES = ['user', 'product', 'cart', 'order', 'payment', 'notification']
REPO = '111111111111.dkr.ecr.ap-southeast-1.amazonaws.com/lesson14/'
CLOUDFRONT = 'https://d111111abcdef8.cloudfront.net'
API = 'https://abc123defg.execute-api.ap-southeast-1.amazonaws.com'

def emit(value):
    print(value)
    sys.exit(0)

def arg(flag):
    return args[args.index(flag) + 1]

if tool == 'terraform':
    assert args[0].startswith('-chdir=') and args[0].endswith('/terraform/environments/dev'), args
    rest = args[1:]
    if rest[:2] == ['output', '-raw']:
        emit({'cluster_name': 'lesson14-dev', 'cloudfront_url': CLOUDFRONT,
              'api_endpoint': API}[rest[2]])
    if rest[:2] == ['output', '-json']:
        if rest[2] == 'service_names':
            emit(json.dumps({s: 'lesson14-dev-' + s for s in SERVICES}))
        if rest[2] == 'ecr_repository_urls':
            emit(json.dumps({s: REPO + s for s in SERVICES + ['db-init']}))
    raise AssertionError(('Unexpected terraform call', args))

if tool == 'curl':
    url = args[-1]
    if url.startswith(CLOUDFRONT):
        assert '--fail-with-body' in args, args
        emit('200')
    if url.startswith(API):
        assert '--fail-with-body' not in args, args
        emit('200' if scenario == 'direct_url_not_403' else '403')
    raise AssertionError(('Unexpected curl URL', url))

assert tool == 'aws', tool
assert arg('--region') == 'ap-southeast-1', args
if args[:3] == ['ecs', 'wait', 'services-stable']:
    assert arg('--cluster') == 'lesson14-dev'
    sys.exit(255 if scenario == 'wait_failed' and arg('--services') == 'lesson14-dev-order' else 0)
if args[:2] == ['ecs', 'describe-services']:
    query = arg('--query')
    assert "status=='PRIMARY'" in query, query
    service = arg('--services')
    if query.endswith('rolloutState | [0]'):
        emit('FAILED' if scenario == 'rollout_failed' and service == 'lesson14-dev-cart' else 'COMPLETED')
    assert query.endswith('taskDefinition | [0]'), query
    emit('arn:aws:ecs:ap-southeast-1:111111111111:task-definition/' + service + ':7')
if args[:2] == ['ecs', 'describe-task-definition']:
    assert "name=='app'" in arg('--query')
    svc = arg('--task-definition').rsplit('/', 1)[1].split(':')[0].removeprefix('lesson14-dev-')
    tag = 'v1' if scenario == 'rollback' and svc == 'payment' else 'v2'
    emit(REPO + svc + ':' + tag)
raise AssertionError(('Unexpected or mutating AWS operation', args))
'''


class ReleaseCheckTest(unittest.TestCase):
    def run_checker(self, scenario, tag="v2", region="ap-southeast-1"):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            for tool in ("terraform", "aws", "curl"):
                command = folder / tool
                command.write_text(f"#!{sys.executable}\n" + STUB)
                command.chmod(0o755)
            calls = folder / "calls.jsonl"
            environment = dict(os.environ, PATH=f"{folder}:{os.environ['PATH']}",
                               AWS_REGION=region, CHECK_SCENARIO=scenario,
                               CHECK_CALLS=str(calls))
            result = subprocess.run(["bash", str(CHECKER), tag], env=environment,
                                    text=True, capture_output=True)
            recorded = [json.loads(line) for line in calls.read_text().splitlines()] if calls.exists() else []
            return result, recorded

    def test_success_checks_all_six_services_and_prints_cloudfront_url(self):
        result, calls = self.run_checker("success")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, CLOUDFRONT + "\n")
        waited = [args[args.index("--services") + 1] for tool, args in calls
                  if tool == "aws" and args[:3] == ["ecs", "wait", "services-stable"]]
        self.assertEqual(waited, ["lesson14-dev-" + s for s in SERVICES])
        definitions = [args for tool, args in calls
                       if tool == "aws" and args[:2] == ["ecs", "describe-task-definition"]]
        self.assertEqual(len(definitions), 6)
        self.assertEqual([args[-1] for tool, args in calls if tool == "curl"],
                         [CLOUDFRONT + "/api/products", API + "/api/products"])

    def test_rollback_on_any_service_fails(self):
        for scenario in ("rollback", "rollout_failed", "wait_failed", "direct_url_not_403"):
            with self.subTest(scenario=scenario):
                result, calls = self.run_checker(scenario)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                if scenario != "direct_url_not_403":
                    self.assertFalse(any(tool == "curl" for tool, _ in calls))
        result, _ = self.run_checker("rollback")
        self.assertIn("lesson14-dev-payment image is", result.stderr)
        self.assertIn("lesson14/payment:v1", result.stderr)
        result, _ = self.run_checker("rollout_failed")
        self.assertIn("lesson14-dev-cart primary rollout is FAILED", result.stderr)

    def test_release_check_uses_cloudfront_only(self):
        result, calls = self.run_checker("success")
        self.assertEqual(result.returncode, 0, result.stderr)
        curls = [args for tool, args in calls if tool == "curl"]
        direct = [args for args in curls if "execute-api" in args[-1]]
        self.assertEqual(len(direct), 1)
        self.assertEqual(direct[0][-1], API + "/api/products")
        self.assertIn("%{http_code}", direct[0])
        self.assertNotIn("--fail-with-body", direct[0])
        self.assertTrue(all(args[-1].startswith(CLOUDFRONT) for args in curls if args not in direct))
        self.assertEqual(result.stdout.strip(), CLOUDFRONT)
        self.assertNotIn("execute-api", result.stdout)

        result, _ = self.run_checker("direct_url_not_403")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("expected 403", result.stderr)

    def test_tag_required_before_any_command(self):
        for tag, region in (("", "ap-southeast-1"), ("v2'; bad", "ap-southeast-1"),
                            ("-v2", "ap-southeast-1"), ("v2", "")):
            with self.subTest(tag=tag, region=region):
                result, calls = self.run_checker("success", tag=tag, region=region)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
