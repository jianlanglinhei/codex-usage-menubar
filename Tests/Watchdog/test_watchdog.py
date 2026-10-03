import os, subprocess, tempfile, pathlib, time, sys
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
        ('low-battery',20,30,'normal'),
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
        p=subprocess.Popen(['/bin/sh','-c',script],env=env)
        if mode in ('remove','exit','hot','restorefail'):
            time.sleep(.3)
            if child: child.terminate();child.wait()
            elif mode in ('hot','restorefail'): marker.write_text('overheat')
            else:marker.unlink()
        p.wait(timeout=8)
        calls=log.read_text().splitlines()
        expected=['-a disablesleep 1','-a disablesleep 0'] + (['sleepnow'] if mode=='hot' else [])
        assert calls==expected,(name,calls)
        print('PASS',name)
