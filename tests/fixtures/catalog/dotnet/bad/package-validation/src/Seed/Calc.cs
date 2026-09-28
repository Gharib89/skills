namespace Seed;

public static class Calc
{
    public static int Add(int a, int b) => a + b;

#if NETSTANDARD2_0
    public static int Sub(int a, int b) => a - b;
#endif
}
