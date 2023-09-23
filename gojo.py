from os import system, chdir, mkdir
from pathlib import Path
counter = 0

if system("cargo build") != 0:
    exit(1)

try:
    mkdir("/tmp/sk-wp")
except FileExistsError:
    pass

rt = Path("./target/debug/touka").resolve().as_posix()
chdir("/tmp/sk-wp")

def sukuna(expr):
    global counter
    print(f'test {expr}: ', end='', flush=True)

    counter += 1
    name = f"/tmp/sk-{counter:03}-test"
    with open(name, 'w') as f:
        f.write(expr)
    system(f"{rt} {name}")
    system("tcc -run output.c")
    

for op in ["*", "-", "/", "*", "%", "<", ">", "<=", ">="]:
    sukuna(f"print(2 {op} 2)")

sukuna("print(2 == 2)")
sukuna("print(2 != 2)")


