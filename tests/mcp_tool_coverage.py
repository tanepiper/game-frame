#!/usr/bin/env python3
"""Check GameFrame's full MCP catalog and runnable tool surface against the sample game.

Usage: tests/mcp_tool_coverage.py (called by tests/run.sh after the sample game is built).
Inputs: the checked-out GameFrame catalog and examples/sample-game/build/game.exe.
Outputs: fails on a missing MCP listing/help route, a failed runner dispatch, or broken
progress, cancellation or timeout handling. It runs help commands in a temporary project.
"""
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / 'tools/gameframe'), str(ROOT / 'tools')]

import catalog
from mcp_server.context import RequestContext
from mcp_server.toolsets import runner


class Client:
    def __init__(self, project):
        env = {key: value for key, value in os.environ.items()
               if not key.startswith(('CLAUDE', 'ANTHROPIC_'))}
        env.update({'GAMEFRAME_PROJECT': str(project), 'GAMEFRAME_NO_DOTENV': '1'})
        self.process = subprocess.Popen(
            [str(ROOT / 'gameframe'), 'serve'], cwd=ROOT, env=env,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, bufsize=1)
        self.sequence = 0

    def request(self, method, params=None):
        self.sequence += 1
        request_id = self.sequence
        message = {'jsonrpc': '2.0', 'id': request_id, 'method': method}
        if params is not None:
            message['params'] = params
        self.process.stdin.write(json.dumps(message) + '\n')
        self.process.stdin.flush()
        while True:
            line = self.process.stdout.readline()
            if not line:
                stderr = self.process.stderr.read()
                raise AssertionError(f'MCP server exited before replying: {stderr}')
            reply = json.loads(line)
            if reply.get('id') == request_id:
                if 'error' in reply:
                    raise AssertionError(reply['error'])
                return reply['result']

    def tool(self, name, arguments=None):
        result = self.request('tools/call', {
            'name': name, 'arguments': arguments or {}})
        content = result['content']
        assert len(content) == 1 and content[0]['type'] == 'text', content
        text = content[0]['text']
        try:
            value = json.loads(text)
        except json.JSONDecodeError:
            value = text
        return result, value

    def close(self):
        self.process.stdin.close()
        code = self.process.wait(timeout=10)
        assert code == 0, self.process.stderr.read()


def test_catalog_and_runner():
    expected_tools = {
        'advise', 'knowhow_entry', 'knowhow_list', 'find',
        'gameframe_steps', 'gameframe_skills', 'gameframe_skill', 'gameframe_agents',
        'gameframe_tool_catalog', 'gameframe_tool_help', 'gameframe_progress',
        'gameframe_mcp_providers', 'gameframe_run_tool'}
    items = catalog.tools()
    expected = [item.as_dict() for item in items]
    runnable = [item for item in items if item.runs]
    nonrunnable = [item for item in items if not item.runs]
    assert len(items) == 132, f'catalog has {len(items)} items; update the expected count'
    assert len(runnable) == 103, f'catalog has {len(runnable)} runnable items; update the expected count'
    assert any(item.name == 'ps2_emu' and item.runs for item in items)
    assert any(item.name == 'ps2_sif0' and item.runs for item in items)
    assert len([item for item in items if item.kind == 'library']) == 20
    assert len([item for item in items if item.kind == 'ghidra']) == 9

    with tempfile.TemporaryDirectory(prefix='gameframe-mcp-coverage-') as project:
        client = Client(project)
        try:
            initialized = client.request('initialize', {'protocolVersion': '2025-06-18'})
            assert initialized['capabilities'] == {'tools': {}}
            listed = {item['name'] for item in client.request('tools/list')['tools']}
            assert listed == expected_tools, listed

            catalog_result, actual = client.tool('gameframe_tool_catalog')
            assert not catalog_result['isError'] and actual == expected

            for item in items:
                result, help_item = client.tool('gameframe_tool_help', {'name': item.name})
                assert not result['isError'], (item.name, help_item)
                assert help_item['name'] == item.name
                assert help_item['path'] == item.as_dict()['path']
                assert help_item['kind'] == item.kind
                assert help_item['runs'] is item.runs
                assert help_item['doc'].strip(), item.name

            # Every runnable program and script must resolve through the MCP runner.
            # --help is the documented no-side-effect entry point; the process runs in a
            # temporary project so a tool cannot leave output in this checkout.
            for item in runnable:
                result, output = client.tool('gameframe_run_tool', {
                    'name': item.name, 'args': ['--help'], 'timeout_seconds': 15})
                assert isinstance(output, dict), (item.name, output)
                assert output['tool'] == item.name
                assert output['status'] == 'completed', (item.name, output['status'])
                assert output['stdout'] or output['stderr'], item.name

            for item in nonrunnable:
                result, message = client.tool('gameframe_run_tool', {'name': item.name})
                assert result['isError'], item.name
                if item.kind == 'ghidra':
                    assert 'ghidra-run' in message, (item.name, message)
                else:
                    assert 'library' in message, (item.name, message)

            ghidra_names = {item.name for item in items if item.kind == 'ghidra'}
            assert ghidra_names and {'ghidra-run', 'ghidra-export'} <= {
                item.name for item in runnable}

            sample = ROOT / 'examples/sample-game/build/game.exe'
            result, output = client.tool('gameframe_run_tool', {
                'name': 'peinfo', 'args': [str(sample)]})
            assert not result['isError'], output
            assert output['status'] == 'completed' and output['exit_code'] == 0, output
            assert 'EXE, x64 (64-bit)' in output['stdout'], output['stdout']

            providers_result, providers = client.tool('gameframe_mcp_providers')
            assert not providers_result['isError']
            configured = json.loads((ROOT / '.mcp.json').read_text())['mcpServers']
            assert {item['name'] for item in providers['providers']} == set(configured)
        finally:
            client.close()


def test_progress_cancellation_and_timeout():
    with tempfile.TemporaryDirectory(prefix='gameframe-mcp-runner-') as folder:
        project = Path(folder)
        script = project / 'fixture.py'
        item = catalog.Tool('mcp-runner-fixture', script, 'program', 'test', 'fixture')
        args = {'name': item.name, 'args': [], 'max_output_bytes': 4096}

        def invoke(context, timeout):
            with patch.object(runner.catalog, 'find', return_value=(item, [])), \
                    patch.dict(os.environ, {'GAMEFRAME_PROJECT': str(project)}):
                return runner._run({**args, 'timeout_seconds': timeout}, context)

        script.write_text('import time\nprint("ready", flush=True)\ntime.sleep(1.25)\nprint("done")\n')
        progress = []
        result = invoke(RequestContext('progress', 'token', progress.append), 5)
        assert result.value['status'] == 'completed', result.value
        assert any(message['params'].get('message', '').endswith('is still running')
                   for message in progress), progress
        assert any(message['params'].get('message', '').endswith('finished')
                   for message in progress), progress

        marker = project / 'started'
        script.write_text('import pathlib, sys, time\n'
                          'pathlib.Path(sys.argv[1]).write_text("yes")\n'
                          'time.sleep(20)\n')
        context = RequestContext('cancel', 'token')
        cancelled = []
        worker = threading.Thread(target=lambda: cancelled.append(
            invoke(context, 10,)), daemon=True)
        # Add the marker as a command argument after the helper's default argument list.
        args['args'] = [str(marker)]
        worker.start()
        deadline = time.monotonic() + 5
        while not marker.exists() and time.monotonic() < deadline:
            time.sleep(0.02)
        started = marker.exists()
        context.cancelled.set()
        worker.join(timeout=5)
        assert started, 'fixture process did not start'
        assert not worker.is_alive(), 'cancelled process was not reaped'
        assert cancelled[0].value['status'] == 'cancelled', cancelled[0].value

        script.write_text('import time\ntime.sleep(20)\n')
        args['args'] = []
        timed = invoke(RequestContext('timeout', 'token'), 1)
        assert timed.value['status'] == 'timed_out', timed.value
        assert timed.value['exit_code'] is not None, timed.value


def main():
    test_catalog_and_runner()
    test_progress_cancellation_and_timeout()
    print('MCP coverage: 132 catalog entries, 103 runnable tools, progress/cancel/timeout')


if __name__ == '__main__':
    main()
