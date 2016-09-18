worker_processes 5
preload_app true
timeout 120
listen '/tmp/unicorn_isutar.sock'
stdout_path "/tmp/unicorn/isutar.log"
stderr_path "/tmp/unicorn/isutar.log"
