cargo build

for f in ./s2/*
do
    target/debug/touka $f
    echo -n "$f: "; tcc -run output.c 
done