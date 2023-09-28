from os import system, chdir, mkdir, remove, removedirs, rename, getenv
from pathlib import Path
from tempfile import gettempdir

base = gettempdir()
counter = 0

if system("cargo build") != 0:
    exit(1)

try:
    mkdir(f"{base}/sk-wp")
except FileExistsError:
    pass

rt = Path("./target/debug/touka").resolve().as_posix()
chdir(f"{base}/sk-wp")
flags = ""

if getenv("GOJO_DBG") == "1":
    flags += "-Ddbg"

def sukuna(expr):
    global counter
    counter += 1
    name = f"{base}/sk-{counter:03}-test"
    toutput = f"{base}\Test {counter}.c"

    print(f'Test {toutput}\n\t> {expr}\n\tres: ', end='', flush=True)


    with open(name, 'w') as f:
        f.write(expr)
    
    if system(f"{rt} {name}") != 0:
        print('unable to transpile source.')
        remove(name)
        return

    system(f"tcc {flags} -run output.c")
    try:
        remove(toutput)
    except:
        pass
    rename("output.c", toutput)
    remove(name)

for op in ["*", "-", "/", "*", "%", "<", ">", "<=", ">=", "==", "!="]:
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
sukuna('let a = 2; let b = 4; print(a+b)')
sukuna('let z = 8; let y = z - 2; print (y-z)')

for op in ["*", "-", "/", "*", "%", "<", ">", "<=", ">=", "==", "!="]:
    sukuna(f'let z = 8; let y = z - 2; print (y {op} z)')


for op in ["<", ">", "<=", ">=", "==", "!="]:
    sukuna(f'let z = 8; print (2 {op} z)')
    sukuna(f'let z = 8; print ("2" {op} z)')


sukuna('let x = print((2, 2)); let y = print(("2", 2)); let z = print(("", "")); 0')
sukuna('let x = (2, 2); let y = ("2", 2); let z = (x, y); print(z)')
sukuna('let tuple = (print(1), print(2)); print(tuple)')
sukuna('let _ = print(first((1, 0))); print(second((0, 1)))')
sukuna('let x = (2, 4); print(first(x))')
sukuna('let x = (2, 4); let _ = print(first(x)); print((second(x)))')
chdir("../")

removedirs(f"{base}/sk-wp")