"""Run the real release checker against command stubs; no AWS or HTTP requests."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


CHECKER = Path(__file__).with_name("check-release.sh")
STUB = r'''
import json, os, sys
from pathlib import Path

tool = Path(sys.argv[0]).name
args = sys.argv[1:]
scenario = os.environ['CHECK_SCENARIO']
with open(os.environ['CHECK_CALLS'], 'a') as log:
    log.write(json.dumps([tool, args]) + '\n')
if tool == 'terraform':
    assert Path.cwd().name == os.environ['CHECK_ENVIRONMENT']

def emit(value):
    print(value)
    sys.exit(0)

if tool == 'terraform':
    assert args[:2] == ['output', '-raw'], args
    emit({'cluster_name': 'lab', 'service_name': 'lab',
          'ecr_repository_url': '111111111111.dkr.ecr.ap-southeast-1.amazonaws.com/lab-api',
          'api_url': 'http://lab.ap-southeast-1.elb.amazonaws.com',
          'target_group_arn': 'target-group'}[args[2]])
if tool == 'curl':
    assert '--fail-with-body' in args and '--max-time' in args
    if scenario == 'not_ready' and args[-1].endswith('/ready'):
        print('curl: HTTP 503', file=sys.stderr)
        sys.exit(22)
    emit('{"status":"ok"}' if args[-1].endswith('/health') else '{"status":"ready"}')
assert tool == 'aws'
if args[:3] == ['elbv2', 'wait', 'target-in-service']:
    assert args[args.index('--targets') + 1] == 'Id=10.1.1.10,Port=8080'
    sys.exit(255 if scenario == 'target_unhealthy' else 0)
if args[:2] == ['sts', 'get-caller-identity']:
    emit('222222222222' if scenario == 'wrong_account' else '111111111111')
if args[:3] == ['ecs', 'wait', 'services-stable']:
    sys.exit(255 if scenario == 'wait_failed' else 0)
query = args[args.index('--query') + 1]
if args[:2] == ['ecs', 'describe-services']:
    emit('definition:2' if query.endswith('.taskDefinition') else 'COMPLETED')
if args[:2] == ['ecs', 'describe-task-definition']:
    tag = 'v1' if scenario == 'rollback' else 'v2'
    emit('111111111111.dkr.ecr.ap-southeast-1.amazonaws.com/lab-api:' + tag)
if args[:2] == ['ecs', 'list-tasks']:
    emit('None' if scenario == 'no_tasks' else 'task-old\ntask-new')
if args[:2] == ['ecs', 'describe-tasks']:
    if 'taskDefinitionArn' in query:
        assert args[args.index('--tasks') + 1:args.index('--query')] == ['task-old', 'task-new']
        assert "taskDefinitionArn=='definition:2'" in query
        assert "lastStatus=='RUNNING'" in query and "healthStatus=='HEALTHY'" in query
        emit('None' if scenario == 'unhealthy' else 'task-new')
    assert args[args.index('--tasks') + 1] == 'task-new'
    if 'privateIPv4Address' in query:
        emit('None' if scenario == 'no_private_ip' else '10.1.1.10')
    emit('None' if scenario == 'no_eni' else 'eni-new')
if args[:2] == ['ec2', 'describe-network-interfaces']:
    assert args[args.index('--network-interface-ids') + 1] == 'eni-new'
    emit('None' if scenario == 'no_ip' else '198.51.100.22')
raise AssertionError(('Unexpected or mutating AWS operation', args))
'''


class ReleaseCheckTest(unittest.TestCase):
    def run_checker(self, scenario, tag="v2", region="ap-southeast-1", deployment=None):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            for tool in ("terraform", "aws", "curl"):
                command = folder / tool
                command.write_text(f"#!{sys.executable}\n" + STUB)
                command.chmod(0o755)
            calls = folder / "calls.jsonl"
            environment = dict(os.environ, PATH=f"{folder}:{os.environ['PATH']}",
                               AWS_REGION=region, CHECK_SCENARIO=scenario,
                               CHECK_ENVIRONMENT=deployment or "dev",
                               CHECK_CALLS=str(calls))
            command = ["bash", str(CHECKER), tag]
            if deployment is not None:
                command.append(deployment)
            result = subprocess.run(command, env=environment,
                                    text=True, capture_output=True)
            recorded = [json.loads(line) for line in calls.read_text().splitlines()] if calls.exists() else []
            return result, recorded

    def test_success_selects_new_task_and_prints_only_verified_url(self):
        result, calls = self.run_checker("success")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "http://198.51.100.22:8080\n")
        self.assertIn("Verified task task-new", result.stderr)
        self.assertEqual([args[-1] for tool, args in calls if tool == "curl"],
                         ["http://198.51.100.22:8080/health", "http://198.51.100.22:8080/ready"])

    def test_failed_checks_never_report_a_verified_url(self):
        for scenario in ("wrong_account", "wait_failed", "rollback", "no_tasks",
                         "unhealthy", "no_eni", "no_ip", "not_ready"):
            with self.subTest(scenario=scenario):
                result, calls = self.run_checker(scenario)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                if scenario != "not_ready":
                    self.assertFalse(any(tool == "curl" for tool, _ in calls))

    def test_tag_and_region_are_required_before_any_external_command(self):
        for tag, region in (("v2'; bad", "ap-southeast-1"), ("v2", "")):
            with self.subTest(tag=tag, region=region):
                result, calls = self.run_checker("success", tag=tag, region=region)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(calls, [])

    def test_staging_uses_alb_and_waits_for_private_target(self):
        result, calls = self.run_checker("success", deployment="staging")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "http://lab.ap-southeast-1.elb.amazonaws.com\n")
        self.assertFalse(any(tool == "aws" and args[0] == "ec2" for tool, args in calls))
        self.assertTrue(any(args[:3] == ["elbv2", "wait", "target-in-service"] for _, args in calls))
        self.assertEqual([args[-1] for tool, args in calls if tool == "curl"],
                         ["http://lab.ap-southeast-1.elb.amazonaws.com/health",
                          "http://lab.ap-southeast-1.elb.amazonaws.com/ready"])

    def test_staging_failure_never_reports_a_verified_url(self):
        for scenario in ("rollback", "no_private_ip", "target_unhealthy", "not_ready"):
            with self.subTest(scenario=scenario):
                result, _ = self.run_checker(scenario, deployment="staging")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")

    def test_unknown_environment_is_rejected_before_external_commands(self):
        result, calls = self.run_checker("success", deployment="../prod")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
