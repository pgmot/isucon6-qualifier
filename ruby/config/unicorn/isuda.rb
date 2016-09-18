worker_processes 5
preload_app true
timeout 120
listen '/tmp/unicorn_isuda.sock'
stdout_path "/tmp/unicorn/isuda.log"
stderr_path "/tmp/unicorn/isuda.log"
