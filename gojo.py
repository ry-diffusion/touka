from os import system, chdir, mkdir, remove, removedirs
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
    
    if system(f"{rt} {name}") != 0:
        print('unable to transpile source.')
        remove(name)
        return

    system("tcc -run output.c")
    remove("output.c")
    remove(name)

for op in ["*", "-", "/", "*", "%", "<", ">", "<=", ">="]:
    sukuna(f"print(2 {op} 2)")

sukuna('print("2" + "2")')
sukuna("print(2 == 2)")
sukuna("print(2 != 2)")
sukuna("print(print(1) + print(2))")
sukuna('print (if ("dalva" == "matagal") { 2 } else { 4 })')
sukuna('print (if ("dois" == "dois") { "sim" } else { "nao" })')
sukuna('print (if (2 == 2) { "sim" } else { "nao" })')


removedirs("/tmp/sk-wp")