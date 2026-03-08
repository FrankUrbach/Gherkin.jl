@testset "Tag expression language" begin

    @testset "Empty expression matches all" begin
        expr = parse_tag_expr("")
        @test expr isa TagAll
        @test eval_tag_expr(expr, Set{String}())
        @test eval_tag_expr(expr, Set(["any", "tag"]))
    end

    @testset "Single tag literal" begin
        expr = parse_tag_expr("smoke")
        @test expr isa TagLiteral
        @test expr.name == "smoke"
        @test  eval_tag_expr(expr, Set(["smoke"]))
        @test !eval_tag_expr(expr, Set(["other"]))
        @test !eval_tag_expr(expr, Set{String}())
    end

    @testset "@ prefix stripped" begin
        expr = parse_tag_expr("@smoke")
        @test expr isa TagLiteral
        @test expr.name == "smoke"
        @test eval_tag_expr(expr, Set(["smoke"]))
    end

    @testset "NOT expression" begin
        expr = parse_tag_expr("not @wip")
        @test expr isa TagNot
        @test  eval_tag_expr(expr, Set{String}())
        @test  eval_tag_expr(expr, Set(["smoke"]))
        @test !eval_tag_expr(expr, Set(["wip"]))
    end

    @testset "AND expression" begin
        expr = parse_tag_expr("@smoke and @fast")
        @test expr isa TagAnd
        @test  eval_tag_expr(expr, Set(["smoke", "fast"]))
        @test !eval_tag_expr(expr, Set(["smoke"]))
        @test !eval_tag_expr(expr, Set(["fast"]))
        @test !eval_tag_expr(expr, Set{String}())
    end

    @testset "OR expression" begin
        expr = parse_tag_expr("@smoke or @fast")
        @test expr isa TagOr
        @test  eval_tag_expr(expr, Set(["smoke"]))
        @test  eval_tag_expr(expr, Set(["fast"]))
        @test  eval_tag_expr(expr, Set(["smoke", "fast"]))
        @test !eval_tag_expr(expr, Set{String}())
    end

    @testset "Complex expression with parens" begin
        expr = parse_tag_expr("(@smoke or @fast) and not @wip")
        @test  eval_tag_expr(expr, Set(["smoke"]))
        @test  eval_tag_expr(expr, Set(["fast"]))
        @test !eval_tag_expr(expr, Set(["smoke", "wip"]))
        @test !eval_tag_expr(expr, Set(["wip"]))
        @test !eval_tag_expr(expr, Set{String}())
    end

    @testset "Case-insensitive keywords" begin
        expr = parse_tag_expr("@smoke AND NOT @wip")
        @test  eval_tag_expr(expr, Set(["smoke"]))
        @test !eval_tag_expr(expr, Set(["smoke", "wip"]))
    end

    @testset "Operator precedence: not > and > or" begin
        # a or b and not c  ≡  a or (b and (not c))
        expr = parse_tag_expr("a or b and not c")
        @test  eval_tag_expr(expr, Set(["a"]))           # a is true
        @test  eval_tag_expr(expr, Set(["b"]))           # b and (not c) with c absent
        @test !eval_tag_expr(expr, Set(["b", "c"]))      # b and (not c) fails because c is present
        @test  eval_tag_expr(expr, Set(["a", "b", "c"])) # a is true
    end

    @testset "Double NOT" begin
        expr = parse_tag_expr("not not @smoke")
        @test  eval_tag_expr(expr, Set(["smoke"]))
        @test !eval_tag_expr(expr, Set{String}())
    end

    @testset "Whitespace-only is TagAll" begin
        expr = parse_tag_expr("   ")
        @test expr isa TagAll
    end
end
