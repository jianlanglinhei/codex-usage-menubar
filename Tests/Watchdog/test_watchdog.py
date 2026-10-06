import os, subprocess, tempfile, pathlib, time, sys, json, signal, select
generator = pathlib.Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix='codexusage-check-') as temp:
    root=pathlib.Path(temp)
    pmset=root/'pmset'
    log=root/'calls'
    pmset.write_text('''#!/bin/sh
if [ "$1" = "-g" ]; then
  printf "Now drawing from 'Battery Power'\\n -InternalBattery-0 (id=1)\\t${TEST_BATTERY:-49}%%; discharging; 1:20 remaining present: true\\n"
else
  echo "$*" >> "$TEST_LOG"
  if [ "${TEST_FAIL:-0}" = 1 ] && [ "$3" = 1 ]; then exit 1; fi
  if [ "${TEST_RESTORE_FAIL:-0}" = 1 ] && [ "$3" = 0 ]; then exit 1; fi
fi
''')
    pmset.chmod(0o755)
    for name,battery,seconds,mode in [
        ('timeout',49,1,'normal'),
        ('low-battery',20,30,'low'),
        ('invalid-battery','unknown',30,'invalid'),
        ('stop',49,30,'remove'),
        ('app-exit',49,30,'exit'),
        ('stale-lease',49,30,'stale'),
        ('enable-failure',49,30,'fail'),
        ('overheat',49,30,'hot'),
        ('restore-failure',49,30,'restorefail')]:
        marker=root/'lease';marker.write_text('normal');log.write_text('')
        child=subprocess.Popen(['/bin/sleep','40']) if mode=='exit' else None
        pid=child.pid if child else os.getpid()
        script=subprocess.check_output([str(generator),str(pid),str(marker),str(seconds)],text=True)
        script=script.replace('/usr/bin/pmset',"'"+str(pmset)+"'")
        if mode=='stale':
            os.utime(marker,(time.time()-60,time.time()-60))
            script=script.replace('-ge 10','-ge 0')
        subprocess.run(['/bin/sh','-n'],input=script,text=True,check=True)
        env=dict(os.environ,TEST_LOG=str(log),TEST_BATTERY=str(battery),TEST_FAIL='1' if mode=='fail' else '0',TEST_RESTORE_FAIL='1' if mode=='restorefail' else '0')
        p=subprocess.Popen(['/bin/sh','-c',script],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
        assert select.select([p.stdout],[],[],5)[0],(name,'startup timed out')
        startup=p.stdout.readline()
        if mode in ('remove','exit','hot','restorefail'):
            assert 'CODEX_USAGE_READY' in startup,(name,startup)
            if child: child.terminate();child.wait()
            elif mode in ('hot','restorefail'): marker.write_text('overheat')
            else:marker.unlink()
        output,_=p.communicate(timeout=8)
        output=startup+output
        calls=log.read_text().splitlines()
        expected=[] if mode in ('low','invalid') else ['-a disablesleep 1','-a disablesleep 0'] + (['sleepnow'] if mode=='hot' else [])
        assert calls==expected,(name,calls)
        expected_status={'low':'CODEX_USAGE_ERROR:battery:1','invalid':'CODEX_USAGE_ERROR:battery:2','fail':'CODEX_USAGE_ERROR:pmset'}.get(mode,'CODEX_USAGE_READY')
        assert expected_status in output,(name,output)
        print('PASS',name)

    # Exercise the actual AppleScript/background-shell handoff, with only pmset mocked.
    # A shell dispatch exit code alone must never be interpreted as a successful start.
    for battery,expected_status in [(96,'CODEX_USAGE_READY'),(20,'CODEX_USAGE_ERROR:battery:1')]:
        marker=root/'lease';marker.write_text('normal');log.write_text('')
        pidfile=root/'pid'
        mock_script=pmset.read_text().replace('${TEST_BATTERY:-49}',str(battery)).replace('$TEST_LOG',str(log))
        launch_pmset=root/'launch-pmset';launch_pmset.write_text(mock_script);launch_pmset.chmod(0o755)
        command=subprocess.check_output([str(generator),str(os.getpid()),str(marker),'30','--launcher'],text=True)
        command=command.replace('/usr/bin/pmset',str(launch_pmset))
        # Insert only a test probe into the generated child script to send it a hangup.
        command=command.replace('overheated=0',f'echo $$ > {pidfile}\noverheated=0')
        try:
            result=subprocess.run(['/usr/bin/osascript','-e','do shell script '+json.dumps(command)],capture_output=True,text=True,timeout=5,check=True)
            assert expected_status in result.stdout,result
            if battery==96:
                assert log.read_text().splitlines()==['-a disablesleep 1']
                os.kill(int(pidfile.read_text()),signal.SIGHUP)
                time.sleep(.2)
                assert log.read_text().splitlines()==['-a disablesleep 1'],'hangup ended the session'
            else:
                assert log.read_text()==''
        finally:
            marker.unlink(missing_ok=True)
            deadline=time.monotonic()+5
            while battery==96 and '-a disablesleep 0' not in log.read_text() and time.monotonic()<deadline:
                time.sleep(.1)
        if battery==96:
            assert log.read_text().splitlines()==['-a disablesleep 1','-a disablesleep 0']
        print('PASS AppleScript launcher',battery,expected_status)
