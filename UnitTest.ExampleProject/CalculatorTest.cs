using System;
using ExampleProject;
using Xunit;

namespace UnitTest.ExampleProject;

public sealed class CalculatorTest
{
    private readonly Calculator _calculator;

    public CalculatorTest()
    {
        _calculator = new Calculator();
    }

    [Trait("Category", "Core Business Logic")]
    [Theory(DisplayName = "Successful to add numbers")]
    [InlineData(5, 5, 10)]
    public void SuccessfulToAddNumbers(int first, int second, int expected)
    {
        // Arrange
        // Act
        int result = _calculator.Add(first, second);

        // Assert
        Assert.Equal(expected, result);
    }

    [Trait("Category", "Core Business Logic")]
    [Theory(DisplayName = "Successful to subtract numbers")]
    [InlineData(5, 5, 0)]
    public void SuccessfulToSubtractNumbers(int first, int second, int expected)
    {
        // Arrange
        // Act
        int result = _calculator.Subtract(first, second);

        // Assert
        Assert.Equal(expected, result);
    }

    [Trait("Category", "Core Business Logic")]
    [Theory(DisplayName = "Successful to multiply numbers")]
    [InlineData(1, 1, 1)]
    public void SuccessfulToMultiplyNumbers(int first, int second, int expected)
    {
        // Arrange
        // Act
        int result = _calculator.Multiply(first, second);

        // Assert
        Assert.Equal(expected, result);
    }

    [Trait("Category", "Core Business Logic")]
    [Theory(DisplayName = "Successful to divide numbers")]
    [InlineData(1, 1, 1, 0)]
    public void SuccessfulToDivideNumbers(int first, int second, int expected, int remainder)
    {
        // Arrange
        // Act
        (int Result, int Remainder) result = _calculator.Divide(first, second);

        // Assert
        Assert.Equal(expected, result.Result);
        Assert.Equal(remainder, result.Remainder);
    }

    [Trait("Category", "Core Business Logic")]
    [Fact(DisplayName = "Fail to divide numbers when divisor is zero")]
    public void FailToDivideNumbersWhenDivisorIsZero()
    {
        // Arrange
        // Act
        // Assert
        Assert.Throws<DivideByZeroException>(() => _calculator.Divide(5, 0));
    }
}