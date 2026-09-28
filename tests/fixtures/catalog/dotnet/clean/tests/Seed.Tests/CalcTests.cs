using Xunit;

namespace Seed.Tests;

public class CalcTests
{
    [Fact]
    public void Adds() => Assert.Equal(3, Calc.Add(1, 2));
}
