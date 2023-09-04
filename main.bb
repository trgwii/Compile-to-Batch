423;
print("Hello");
print("Escaped\"String");
print("Multi", 42, "Params");
foo := 42;

foo = 12;

baz := "Hello";

baz = "World";

qux := 42;

quux :: 999;

bar :: "Hello, World!";
print(foo);

print(bar);

math :: 42 + 84 * 300;

x := 42;

y := 12 + 84;

y = x * y;

print(x, y);

print(x + y);

{
    foo :: 42 + 84;
    bar :: 42 * foo + 18;
    print(bar - foo);

    print(bar - foo, bar + foo);
    print(bar * foo, bar / foo);
}

batch {
    @rem HELLO
}

batch {{
    @echo "}"
}}

p :: print;

batch{echo %RANDOM%}


{
    insideblock := 400;
    print(insideblock);
}

batch {@if "%foo%" GEQ "100" goto :poop}

print("Never prints");

batch {:poop}

print("LOL");

if (foo == 42) {
    print("Yes");
}

if (foo == 84) {
    print("Yes");
} else {
    print("No");
}


ding :: 42 == 42;

print(ding);

if (ding) {
    print("Yuppers");
}

{
    foo := 42;

    while (foo != 50) {
        bar := 42;
        foo = foo + 1;
        bar = foo + 1;
        foo = foo + 1;
        print("foo", foo);
    }
}

add :: (a, b) {
    return a + b;
};

print(add(1, 2));
