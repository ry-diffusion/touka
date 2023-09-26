from os import system, chdir, mkdir, remove, removedirs, rename
from pathlib import Path
from tempfile import gettempdir
counter = 0
base = gettempdir()

if system("cargo build") != 0:
    exit(1)

try:
    mkdir(f"{base}/sk-wp")
except FileExistsError:
    pass

rt = Path("./target/debug/touka").resolve().as_posix()
chdir(f"{base}/sk-wp")

def sukuna(expr):
    global counter
    print(f'test {expr}: ', end='', flush=True)

    counter += 1
    name = f"{base}/sk-{counter:03}-test"
    toutput = f"{base}\Output {counter}.c"

    with open(name, 'w') as f:
        f.write(expr)
    
    if system(f"{rt} {name}") != 0:
        print('unable to transpile source.')
        remove(name)
        return

    system("tcc -Ddbg -run output.c")
    try:
        remove(toutput)
    except:
        pass
    rename("output.c", toutput)
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
sukuna('let x = 2; print(x + 2)')
sukuna('let x = 2; print(2 + x)')
sukuna('let x = "2"; print("2" + x)')
sukuna('let x = "2"; print(x + 2)')
sukuna('let x = "2"; let y = "2" + x; print (y)')
sukuna('let x = "2"; let y = x + 2; print (y)')
chdir("../")

removedirs(f"{base}/sk-wp")