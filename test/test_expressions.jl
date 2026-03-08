@testset "Expressions" begin

    @testset "{int} pattern" begin
        p = compile_pattern("I add {int} and {int}")
        params = match_step(p, "I add 3 and 4")
        @test params !== nothing
        @test length(params) == 2
        @test params[1] === 3
        @test params[2] === 4
        @test params[1] isa Int
        @test params[2] isa Int
    end

    @testset "{int} negative" begin
        p = compile_pattern("value is {int}")
        params = match_step(p, "value is -42")
        @test params !== nothing
        @test params[1] === -42
    end

    @testset "{float} pattern" begin
        p = compile_pattern("result is {float}")
        params = match_step(p, "result is 3.14")
        @test params !== nothing
        @test params[1] isa Float64
        @test params[1] ≈ 3.14
    end

    @testset "{word} pattern" begin
        p = compile_pattern("connection opens with {word}")
        params = match_step(p, "connection opens with admin")
        @test params !== nothing
        @test params[1] == "admin"
        @test params[1] isa String
    end

    @testset "{string} pattern — double quotes" begin
        p = compile_pattern("user is named {string}")
        params = match_step(p, "user is named \"Alice\"")
        @test params !== nothing
        @test params[1] == "Alice"
        @test params[1] isa String
    end

    @testset "{string} pattern — single quotes" begin
        p = compile_pattern("user is named {string}")
        params = match_step(p, "user is named 'Bob'")
        @test params !== nothing
        @test params[1] == "Bob"
    end

    @testset "{bool} pattern" begin
        p = compile_pattern("flag is {bool}")
        params_t = match_step(p, "flag is true")
        @test params_t !== nothing
        @test params_t[1] === true
        @test params_t[1] isa Bool

        params_f = match_step(p, "flag is false")
        @test params_f !== nothing
        @test params_f[1] === false
    end

    @testset "{} anonymous capture" begin
        p = compile_pattern("the result is {}")
        params = match_step(p, "the result is anything goes here")
        @test params !== nothing
        @test params[1] == "anything goes here"
    end

    @testset "{name} custom capture → String" begin
        p = compile_pattern("create database {dbname}")
        params = match_step(p, "create database mydb")
        @test params !== nothing
        @test params[1] == "mydb"
        @test params[1] isa String
    end

    @testset "no match returns nothing" begin
        p = compile_pattern("I add {int} and {int}")
        @test match_step(p, "something else entirely") === nothing
        @test match_step(p, "I add 3 and four") === nothing
    end

    @testset "Regex pattern" begin
        p = compile_pattern(r"connection (\w+) database: (\w+)")
        params = match_step(p, "connection create database: mydb")
        @test params !== nothing
        @test params[1] == "create"
        @test params[2] == "mydb"
    end

    @testset "Regex no match" begin
        p = compile_pattern(r"I have (\d+) items")
        @test match_step(p, "I have no items") === nothing
    end

    @testset "Pattern with no parameters" begin
        p = compile_pattern("a new calculator")
        params = match_step(p, "a new calculator")
        @test params !== nothing
        @test isempty(params)
    end

    @testset "Pattern with dots in literal text" begin
        p = compile_pattern("version 1.0 is installed")
        params = match_step(p, "version 1.0 is installed")
        @test params !== nothing
        # Ensure dot doesn't match arbitrary chars
        @test match_step(p, "version 1X0 is installed") === nothing
    end

    @testset "Multiple {int} captures" begin
        p = compile_pattern("subtract {int} from {int}")
        params = match_step(p, "subtract 2 from 10")
        @test params !== nothing
        @test params[1] === 2
        @test params[2] === 10
    end
end
