#include "barretenberg/stdlib_circuit_builders/ultra_circuit_builder.hpp"
#include "barretenberg/circuit_checker/circuit_checker.hpp"
#include "barretenberg/crypto/pedersen_commitment/pedersen.hpp"
#include "barretenberg/stdlib_circuit_builders/mock_circuits.hpp"
#include "barretenberg/stdlib_circuit_builders/plookup_tables/fixed_base/fixed_base.hpp"

#include <gtest/gtest.h>

using namespace bb;

namespace {
auto& engine = numeric::get_debug_randomness();
}
namespace bb {
using plookup::ColumnIdx;
using plookup::MultiTableId;

TEST(UltraCircuitConstructor, CopyConstructor)
{
    UltraCircuitBuilder circuit_constructor = UltraCircuitBuilder();

    for (size_t i = 0; i < 16; ++i) {
        for (size_t j = 0; j < 16; ++j) {
            uint64_t left = static_cast<uint64_t>(j);
            uint64_t right = static_cast<uint64_t>(i);
            uint32_t left_idx = circuit_constructor.add_variable(fr(left));
            uint32_t right_idx = circuit_constructor.add_variable(fr(right));
            uint32_t result_idx = circuit_constructor.add_variable(fr(left ^ right));

            uint32_t add_idx =
                circuit_constructor.add_variable(fr(left) + fr(right) + circuit_constructor.get_variable(result_idx));
            circuit_constructor.create_big_add_gate(
                { left_idx, right_idx, result_idx, add_idx, fr(1), fr(1), fr(1), fr(-1), fr(0) });
        }
    }

    bool result = CircuitChecker::check(circuit_constructor);
    EXPECT_EQ(result, true);

    UltraCircuitBuilder duplicate_circuit_constructor{ circuit_constructor };

    EXPECT_EQ(duplicate_circuit_constructor.get_estimated_num_finalized_gates(),
              circuit_constructor.get_estimated_num_finalized_gates());
    EXPECT_TRUE(CircuitChecker::check(duplicate_circuit_constructor));
}

TEST(UltraCircuitConstructor, CreateGatesFromPlookupAccumulators)
{

    UltraCircuitBuilder circuit_builder = UltraCircuitBuilder();

    fr input_value = fr::random_element();
    const fr input_lo = static_cast<uint256_t>(input_value).slice(0, plookup::fixed_base::table::BITS_PER_LO_SCALAR);
    const auto input_lo_index = circuit_builder.add_variable(input_lo);

    const auto sequence_data_lo = plookup::get_lookup_accumulators(plookup::MultiTableId::FIXED_BASE_LEFT_LO, input_lo);

    const auto lookup_witnesses = circuit_builder.create_gates_from_plookup_accumulators(
        plookup::MultiTableId::FIXED_BASE_LEFT_LO, sequence_data_lo, input_lo_index);

    const size_t num_lookups = plookup::fixed_base::table::NUM_TABLES_PER_LO_MULTITABLE;

    EXPECT_EQ(num_lookups, lookup_witnesses[plookup::ColumnIdx::C1].size());

    {
        const auto mask = plookup::fixed_base::table::MAX_TABLE_SIZE - 1;

        grumpkin::g1::affine_element base_point = plookup::fixed_base::table::LHS_GENERATOR_POINT;
        std::vector<uint8_t> input_buf;
        write(input_buf, base_point);
        const auto offset_generators =
            grumpkin::g1::derive_generators(input_buf, plookup::fixed_base::table::NUM_TABLES_PER_LO_MULTITABLE);

        grumpkin::g1::element accumulator = base_point;
        uint256_t expected_scalar(input_lo);
        const auto table_bits = plookup::fixed_base::table::BITS_PER_TABLE;
        const auto num_tables = plookup::fixed_base::table::NUM_TABLES_PER_LO_MULTITABLE;
        for (size_t i = 0; i < num_tables; ++i) {

            auto round_scalar = circuit_builder.get_variable(lookup_witnesses[plookup::ColumnIdx::C1][i]);
            auto round_x = circuit_builder.get_variable(lookup_witnesses[plookup::ColumnIdx::C2][i]);
            auto round_y = circuit_builder.get_variable(lookup_witnesses[plookup::ColumnIdx::C3][i]);

            EXPECT_EQ(uint256_t(round_scalar), expected_scalar);

            auto next_scalar = static_cast<uint256_t>(
                (i == num_tables - 1) ? fr(0)
                                      : circuit_builder.get_variable(lookup_witnesses[plookup::ColumnIdx::C1][i + 1]));

            uint256_t slice = static_cast<uint256_t>(round_scalar) - (next_scalar << table_bits);
            EXPECT_EQ(slice, (uint256_t(input_lo) >> (i * table_bits)) & mask);

            grumpkin::g1::affine_element expected_point(accumulator * static_cast<uint256_t>(slice) +
                                                        offset_generators[i]);

            EXPECT_EQ(round_x, expected_point.x);
            EXPECT_EQ(round_y, expected_point.y);
            for (size_t j = 0; j < table_bits; ++j) {
                accumulator = accumulator.dbl();
            }
            expected_scalar >>= table_bits;
        }
    }

    bool result = CircuitChecker::check(circuit_builder);
    EXPECT_EQ(result, true);
}

TEST(UltraCircuitConstructor, BadLookupFailure)
{
    UltraCircuitBuilder builder;
    MockCircuits::add_lookup_gates(builder);

    // Erroneously set a non-zero wire value to zero in one of the lookup gates
    for (auto& wire_3_witness_idx : builder.blocks.lookup.w_o()) {
        if (wire_3_witness_idx != builder.zero_idx) {
            wire_3_witness_idx = builder.zero_idx;
            break;
        }
    }

    EXPECT_FALSE(CircuitChecker::check(builder));
}

TEST(UltraCircuitConstructor, BaseCase)
{
    UltraCircuitBuilder circuit_constructor = UltraCircuitBuilder();
    fr a = fr::one();
    circuit_constructor.add_public_variable(a);
    bool result = CircuitChecker::check(circuit_constructor);
    EXPECT_EQ(result, true);
}
TEST(UltraCircuitConstructor, TestNoLookupProof)
{
    UltraCircuitBuilder circuit_constructor = UltraCircuitBuilder();

    for (size_t i = 0; i < 16; ++i) {
        for (size_t j = 0; j < 16; ++j) {
            uint64_t left = static_cast<uint64_t>(j);
            uint64_t right = static_cast<uint64_t>(i);
            uint32_t left_idx = circuit_constructor.add_variable(fr(left));
            uint32_t right_idx = circuit_constructor.add_variable(fr(right));
            uint32_t result_idx = circuit_constructor.add_variable(fr(left ^ right));

            uint32_t add_idx =
                circuit_constructor.add_variable(fr(left) + fr(right) + circuit_constructor.get_variable(result_idx));
            circuit_constructor.create_big_add_gate(
                { left_idx, right_idx, result_idx, add_idx, fr(1), fr(1), fr(1), fr(-1), fr(0) });
        }
    }

    bool result = CircuitChecker::check(circuit_constructor);
    EXPECT_EQ(result, true);
}

TEST(UltraCircuitConstructor, TestEllipticGate)
{
    typedef grumpkin::g1::affine_element affine_element;
    typedef grumpkin::g1::element element;
    UltraCircuitBuilder circuit_constructor = UltraCircuitBuilder();

    affine_element p1 = crypto::pedersen_commitment::commit_native({ bb::fr(1) }, 0);

    affine_element p2 = crypto::pedersen_commitment::commit_native({ bb::fr(1) }, 1);
    affine_element p3(element(p1) + element(p2));

    uint32_t x1 = circuit_constructor.add_variable(p1.x);
    uint32_t y1 = circuit_constructor.add_variable(p1.y);
    uint32_t x2 = circuit_constructor.add_variable(p2.x);
    uint32_t y2 = circuit_constructor.add_variable(p2.y);
    uint32_t x3 = circuit_constructor.add_variable(p3.x);
    uint32_t y3 = circuit_constructor.add_variable(p3.y);

    circuit_constructor.create_ecc_add_gate({ x1, y1, x2, y2, x3, y3, 1 });

    bool result = CircuitChecker::check(circuit_constructor);
    EXPECT_EQ(result, true);

    circuit_constructor.create_ecc_add_gate({ x1 + 1, y1, x2, y2, x3, y3, 1 });

    EXPECT_EQ(CircuitChecker::check(circuit_constructor), false);
}

TEST(UltraCircuitConstructor, TestEllipticDoubleGate)
{
    typedef grumpkin::g1::affine_element affine_element;
    typedef grumpkin::g1::element element;
    UltraCircuitBuilder circuit_constructor = UltraCircuitBuilder();

    affine_element p1 = crypto::pedersen_commitment::commit_native({ bb::fr(1) }, 0);
    affine_element p3(element(p1).dbl());

    uint32_t x1 = circuit_constructor.add_variable(p1.x);
    uint32_t y1 = circuit_constructor.add_variable(p1.y);
    uint32_t x3 = circuit_constructor.add_variable(p3.x);
    uint32_t y3 = circuit_constructor.add_variable(p3.y);

    circuit_constructor.create_ecc_dbl_gate({ x1, y1, x3, y3 });

    bool result = CircuitChecker::check(circuit_constructor);
    EXPECT_EQ(result, true);
}

TEST(UltraCircuitConstructor, NonTrivialTagPermutation)
{
    UltraCircuitBuilder circuit_constructor = UltraCircuitBuilder();
    fr a = fr::random_element();
    fr b = -a;

    auto a_idx = circuit_constructor.add_variable(a);
    auto b_idx = circuit_constructor.add_variable(b);
    auto c_idx = circuit_constructor.add_variable(b);
    auto d_idx = circuit_constructor.add_variable(a);

    circuit_constructor.create_add_gate(
        { a_idx, b_idx, circuit_constructor.zero_idx, fr::one(), fr::one(), fr::zero(), fr::zero() });
    circuit_constructor.create_add_gate(
        { c_idx, d_idx, circuit_constructor.zero_idx, fr::one(), fr::one(), fr::zero(), fr::zero() });

    circuit_constructor.create_tag(1, 2);
    circuit_constructor.create_tag(2, 1);

    circuit_constructor.assign_tag(a_idx, 1);
    circuit_constructor.assign_tag(b_idx, 1);
    circuit_constructor.assign_tag(c_idx, 2);
    circuit_constructor.assign_tag(d_idx, 2);

    bool result = CircuitChecker::check(circuit_constructor);
    EXPECT_EQ(result, true);

    // Break the tag
    circuit_constructor.real_variable_tags[circuit_constructor.real_variable_index[a_idx]] = 2;
    EXPECT_EQ(CircuitChecker::check(circuit_constructor), false);
}

TEST(UltraCircuitConstructor, NonTrivialTagPermutationAndCycles)
{
    UltraCircuitBuilder circuit_constructor = UltraCircuitBuilder();
    fr a = fr::random_element();
    fr c = -a;

    auto a_idx = circuit_constructor.add_variable(a);
    auto b_idx = circuit_constructor.add_variable(a);
    circuit_constructor.assert_equal(a_idx, b_idx);
    auto c_idx = circuit_constructor.add_variable(c);
    auto d_idx = circuit_constructor.add_variable(c);
    circuit_constructor.assert_equal(c_idx, d_idx);
    auto e_idx = circuit_constructor.add_variable(a);
    auto f_idx = circuit_constructor.add_variable(a);
    circuit_constructor.assert_equal(e_idx, f_idx);
    auto g_idx = circuit_constructor.add_variable(c);
    auto h_idx = circuit_constructor.add_variable(c);
    circuit_constructor.assert_equal(g_idx, h_idx);

    circuit_constructor.create_tag(1, 2);
    circuit_constructor.create_tag(2, 1);

    circuit_constructor.assign_tag(a_idx, 1);
    circuit_constructor.assign_tag(c_idx, 1);
    circuit_constructor.assign_tag(e_idx, 2);
    circuit_constructor.assign_tag(g_idx, 2);

    circuit_constructor.create_add_gate(
        { b_idx, a_idx, circuit_constructor.zero_idx, fr::one(), fr::neg_one(), fr::zero(), fr::zero() });
    circuit_constructor.create_add_gate(
        { c_idx, g_idx, circuit_constructor.zero_idx, fr::one(), -fr::one(), fr::zero(), fr::zero() });
    circuit_constructor.create_add_gate(
        { e_idx, f_idx, circuit_constructor.zero_idx, fr::one(), -fr::one(), fr::zero(), fr::zero() });

    bool result = CircuitChecker::check(circuit_constructor);
    EXPECT_EQ(result, true);

    // Break the tag
    circuit_constructor.real_variable_tags[circuit_constructor.real_variable_index[a_idx]] = 2;
    EXPECT_EQ(CircuitChecker::check(circuit_constructor), false);
}
TEST(UltraCircuitConstructor, BadTagPermutation)
{
    UltraCircuitBuilder circuit_constructor = UltraCircuitBuilder();
    fr a = fr::random_element();
    fr b = -a;

    auto a_idx = circuit_constructor.add_variable(a);
    auto b_idx = circuit_constructor.add_variable(b);
    auto c_idx = circuit_constructor.add_variable(b);
    auto d_idx = circuit_constructor.add_variable(a + 1);

    circuit_constructor.create_add_gate({ a_idx, b_idx, circuit_constructor.zero_idx, 1, 1, 0, 0 });
    circuit_constructor.create_add_gate({ c_idx, d_idx, circuit_constructor.zero_idx, 1, 1, 0, -1 });

    bool result = CircuitChecker::check(circuit_constructor);
    EXPECT_EQ(result, true);

    circuit_constructor.create_tag(1, 2);
    circuit_constructor.create_tag(2, 1);

    circuit_constructor.assign_tag(a_idx, 1);
    circuit_constructor.assign_tag(b_idx, 1);
    circuit_constructor.assign_tag(c_idx, 2);
    circuit_constructor.assign_tag(d_idx, 2);

    result = CircuitChecker::check(circuit_constructor);
    EXPECT_EQ(result, false);
}

TEST(UltraCircuitConstructor, SortWidget)
{
    UltraCircuitBuilder circuit_constructor = UltraCircuitBuilder();
    fr a = fr::one();
    fr b = fr(2);
    fr c = fr(3);
    fr d = fr(4);

    auto a_idx = circuit_constructor.add_variable(a);
    auto b_idx = circuit_constructor.add_variable(b);
    auto c_idx = circuit_constructor.add_variable(c);
    auto d_idx = circuit_constructor.add_variable(d);
    circuit_constructor.create_sort_constraint({ a_idx, b_idx, c_idx, d_idx });

    bool result = CircuitChecker::check(circuit_constructor);
    EXPECT_EQ(result, true);
}

std::vector<uint32_t> add_variables(UltraCircuitBuilder& circuit_constructor, std::vector<fr> variables)
{
    std::vector<uint32_t> res;
    for (size_t i = 0; i < variables.size(); i++) {
        res.emplace_back(circuit_constructor.add_variable(variables[i]));
    }
    return res;
}
TEST(UltraCircuitConstructor, SortWithEdgesGate)
{
    fr a = fr::one();
    fr b = fr(2);
    fr c = fr(3);
    fr d = fr(4);
    fr e = fr(5);
    fr f = fr(6);
    fr g = fr(7);
    fr h = fr(8);

    {
        UltraCircuitBuilder circuit_constructor;
        auto a_idx = circuit_constructor.add_variable(a);
        auto b_idx = circuit_constructor.add_variable(b);
        auto c_idx = circuit_constructor.add_variable(c);
        auto d_idx = circuit_constructor.add_variable(d);
        auto e_idx = circuit_constructor.add_variable(e);
        auto f_idx = circuit_constructor.add_variable(f);
        auto g_idx = circuit_constructor.add_variable(g);
        auto h_idx = circuit_constructor.add_variable(h);
        circuit_constructor.create_sort_constraint_with_edges(
            { a_idx, b_idx, c_idx, d_idx, e_idx, f_idx, g_idx, h_idx }, a, h);
        bool result = CircuitChecker::check(circuit_constructor);
        EXPECT_EQ(result, true);
    }

    {
        UltraCircuitBuilder circuit_constructor;
        auto a_idx = circuit_constructor.add_variable(a);
        auto b_idx = circuit_constructor.add_variable(b);
        auto c_idx = circuit_constructor.add_variable(c);
        auto d_idx = circuit_constructor.add_variable(d);
        auto e_idx = circuit_constructor.add_variable(e);
        auto f_idx = circuit_constructor.add_variable(f);
        auto g_idx = circuit_constructor.add_variable(g);
        auto h_idx = circuit_constructor.add_variable(h);
        circuit_constructor.create_sort_constraint_with_edges(
            { a_idx, b_idx, c_idx, d_idx, e_idx, f_idx, g_idx, h_idx }, a, g);

        bool result = CircuitChecker::check(circuit_constructor);
        EXPECT_EQ(result, false);
    }
    {
        UltraCircuitBuilder circuit_constructor;
        auto a_idx = circuit_constructor.add_variable(a);
        auto b_idx = circuit_constructor.add_variable(b);
        auto c_idx = circuit_constructor.add_variable(c);
        auto d_idx = circuit_constructor.add_variable(d);
        auto e_idx = circuit_constructor.add_variable(e);
        auto f_idx = circuit_constructor.add_variable(f);
        auto g_idx = circuit_constructor.add_variable(g);
        auto h_idx = circuit_constructor.add_variable(h);
        circuit_constructor.create_sort_constraint_with_edges(
            { a_idx, b_idx, c_idx, d_idx, e_idx, f_idx, g_idx, h_idx }, b, h);

        bool result = CircuitChecker::check(circuit_constructor);
        EXPECT_EQ(result, false);
    }
    {
        UltraCircuitBuilder circuit_constructor;
        auto a_idx = circuit_constructor.add_variable(a);
        auto c_idx = circuit_constructor.add_variable(c);
        auto d_idx = circuit_constructor.add_variable(d);
        auto e_idx = circuit_constructor.add_variable(e);
        auto f_idx = circuit_constructor.add_variable(f);
        auto g_idx = circuit_constructor.add_variable(g);
        auto h_idx = circuit_constructor.add_variable(h);
        auto b2_idx = circuit_constructor.add_variable(fr(15));
        circuit_constructor.create_sort_constraint_with_edges(
            { a_idx, b2_idx, c_idx, d_idx, e_idx, f_idx, g_idx, h_idx }, b, h);
        bool result = CircuitChecker::check(circuit_constructor);
        EXPECT_EQ(result, false);
    }
    {
        UltraCircuitBuilder circuit_constructor = UltraCircuitBuilder();
        auto idx = add_variables(circuit_constructor, { 1,  2,  5,  6,  7,  10, 11, 13, 16, 17, 20, 22, 22, 25,
                                                        26, 29, 29, 32, 32, 33, 35, 38, 39, 39, 42, 42, 43, 45 });
        circuit_constructor.create_sort_constraint_with_edges(idx, 1, 45);
        bool result = CircuitChecker::check(circuit_constructor);
        EXPECT_EQ(result, true);
    }
    {
        UltraCircuitBuilder circuit_constructor = UltraCircuitBuilder();
        auto idx = add_variables(circuit_constructor, { 1,  2,  5,  6,  7,  10, 11, 13, 16, 17, 20, 22, 22, 25,
                                                        26, 29, 29, 32, 32, 33, 35, 38, 39, 39, 42, 42, 43, 45 });

        circuit_constructor.create_sort_constraint_with_edges(idx, 1, 29);
        bool result = CircuitChecker::check(circuit_constructor);
        EXPECT_EQ(result, false);
    }
}

TEST(UltraCircuitConstructor, RangeConstraint)
{
    {
        UltraCircuitBuilder circuit_constructor = UltraCircuitBuilder();
        auto indices = add_variables(circuit_constructor, { 1, 2, 3, 4, 5, 6, 7, 8 });
        for (size_t i = 0; i < indices.size(); i++) {
            circuit_constructor.create_new_range_constraint(indices[i], 8);
        }
        // auto ind = {a_idx,b_idx,c_idx,d_idx,e_idx,f_idx,g_idx,h_idx};
        circuit_constructor.create_sort_constraint(indices);
        bool result = CircuitChecker::check(circuit_constructor);
        EXPECT_EQ(result, true);
    }
    {
        UltraCircuitBuilder circuit_constructor = UltraCircuitBuilder();
        auto indices = add_variables(circuit_constructor, { 3 });
        for (size_t i = 0; i < indices.size(); i++) {
            circuit_constructor.create_new_range_constraint(indices[i], 3);
        }
        // auto ind = {a_idx,b_idx,c_idx,d_idx,e_idx,f_idx,g_idx,h_idx};
        circuit_constructor.create_dummy_constraints(indices);
        bool result = CircuitChecker::check(circuit_constructor);
        EXPECT_EQ(result, true);
    }
    {
        UltraCircuitBuilder circuit_constructor = UltraCircuitBuilder();
        auto indices = add_variables(circuit_constructor, { 1, 2, 3, 4, 5, 6, 8, 25 });
        for (size_t i = 0; i < indices.size(); i++) {
            circuit_constructor.create_new_range_constraint(indices[i], 8);
        }
        circuit_constructor.create_sort_constraint(indices);
        bool result = CircuitChecker::check(circuit_constructor);
        EXPECT_EQ(result, false);
    }
    {
        UltraCircuitBuilder circuit_constructor = UltraCircuitBuilder();
        auto indices = add_variables(circuit_constructor,
                                     { 1, 2, 3, 4, 5, 6, 10, 8, 15, 11, 32, 21, 42, 79, 16, 10, 3, 26, 19, 51 });
        for (size_t i = 0; i < indices.size(); i++) {
            circuit_constructor.create_new_range_constraint(indices[i], 128);
        }
        circuit_constructor.create_dummy_constraints(indices);
        bool result = CircuitChecker::check(circuit_constructor);
        EXPECT_EQ(result, true);
    }
    {
        UltraCircuitBuilder circuit_constructor = UltraCircuitBuilder();
        auto indices = add_variables(circuit_constructor,
                                     { 1, 2, 3, 80, 5, 6, 29, 8, 15, 11, 32, 21, 42, 79, 16, 10, 3, 26, 13, 14 });
        for (size_t i = 0; i < indices.size(); i++) {
            circuit_constructor.create_new_range_constraint(indices[i], 79);
        }
        circuit_constructor.create_dummy_constraints(indices);
        bool result = CircuitChecker::check(circuit_constructor);
        EXPECT_EQ(result, false);
    }
    {
        UltraCircuitBuilder circuit_constructor = UltraCircuitBuilder();
        auto indices = add_variables(circuit_constructor,
                                     { 1, 0, 3, 80, 5, 6, 29, 8, 15, 11, 32, 21, 42, 79, 16, 10, 3, 26, 13, 14 });
        for (size_t i = 0; i < indices.size(); i++) {
            circuit_constructor.create_new_range_constraint(indices[i], 79);
        }
        circuit_constructor.create_dummy_constraints(indices);
        bool result = CircuitChecker::check(circuit_constructor);
        EXPECT_EQ(result, false);
    }
}

TEST(UltraCircuitConstructor, RangeWithGates)
{
    UltraCircuitBuilder circuit_constructor = UltraCircuitBuilder();
    auto idx = add_variables(circuit_constructor, { 1, 2, 3, 4, 5, 6, 7, 8 });
    for (size_t i = 0; i < idx.size(); i++) {
        circuit_constructor.create_new_range_constraint(idx[i], 8);
    }

    circuit_constructor.create_add_gate(
        { idx[0], idx[1], circuit_constructor.zero_idx, fr::one(), fr::one(), fr::zero(), -3 });
    circuit_constructor.create_add_gate(
        { idx[2], idx[3], circuit_constructor.zero_idx, fr::one(), fr::one(), fr::zero(), -7 });
    circuit_constructor.create_add_gate(
        { idx[4], idx[5], circuit_constructor.zero_idx, fr::one(), fr::one(), fr::zero(), -11 });
    circuit_constructor.create_add_gate(
        { idx[6], idx[7], circuit_constructor.zero_idx, fr::one(), fr::one(), fr::zero(), -15 });
    bool result = CircuitChecker::check(circuit_constructor);
    EXPECT_EQ(result, true);
}

TEST(UltraCircuitConstructor, RangeWithGatesWhereRangeIsNotAPowerOfTwo)
{
    UltraCircuitBuilder circuit_constructor = UltraCircuitBuilder();
    auto idx = add_variables(circuit_constructor, { 1, 2, 3, 4, 5, 6, 7, 8 });
    for (size_t i = 0; i < idx.size(); i++) {
        circuit_constructor.create_new_range_constraint(idx[i], 12);
    }

    circuit_constructor.create_add_gate(
        { idx[0], idx[1], circuit_constructor.zero_idx, fr::one(), fr::one(), fr::zero(), -3 });
    circuit_constructor.create_add_gate(
        { idx[2], idx[3], circuit_constructor.zero_idx, fr::one(), fr::one(), fr::zero(), -7 });
    circuit_constructor.create_add_gate(
        { idx[4], idx[5], circuit_constructor.zero_idx, fr::one(), fr::one(), fr::zero(), -11 });
    circuit_constructor.create_add_gate(
        { idx[6], idx[7], circuit_constructor.zero_idx, fr::one(), fr::one(), fr::zero(), -15 });
    bool result = CircuitChecker::check(circuit_constructor);
    EXPECT_EQ(result, true);
}

TEST(UltraCircuitConstructor, SortWidgetComplex)
{
    {

        UltraCircuitBuilder circuit_constructor = UltraCircuitBuilder();
        std::vector<fr> a = { 1, 3, 4, 7, 7, 8, 11, 14, 15, 15, 18, 19, 21, 21, 24, 25, 26, 27, 30, 32 };
        std::vector<uint32_t> ind;
        for (size_t i = 0; i < a.size(); i++)
            ind.emplace_back(circuit_constructor.add_variable(a[i]));
        circuit_constructor.create_sort_constraint(ind);

        bool result = CircuitChecker::check(circuit_constructor);
        EXPECT_EQ(result, true);
    }
    {

        UltraCircuitBuilder circuit_constructor = UltraCircuitBuilder();
        std::vector<fr> a = { 1, 3, 4, 7, 7, 8, 16, 14, 15, 15, 18, 19, 21, 21, 24, 25, 26, 27, 30, 32 };
        std::vector<uint32_t> ind;
        for (size_t i = 0; i < a.size(); i++)
            ind.emplace_back(circuit_constructor.add_variable(a[i]));
        circuit_constructor.create_sort_constraint(ind);

        bool result = CircuitChecker::check(circuit_constructor);
        EXPECT_EQ(result, false);
    }
}
TEST(UltraCircuitConstructor, SortWidgetNeg)
{
    UltraCircuitBuilder circuit_constructor = UltraCircuitBuilder();
    fr a = fr::one();
    fr b = fr(2);
    fr c = fr(3);
    fr d = fr(8);

    auto a_idx = circuit_constructor.add_variable(a);
    auto b_idx = circuit_constructor.add_variable(b);
    auto c_idx = circuit_constructor.add_variable(c);
    auto d_idx = circuit_constructor.add_variable(d);
    circuit_constructor.create_sort_constraint({ a_idx, b_idx, c_idx, d_idx });

    bool result = CircuitChecker::check(circuit_constructor);
    EXPECT_EQ(result, false);
}

TEST(UltraCircuitConstructor, ComposedRangeConstraint)
{
    UltraCircuitBuilder circuit_constructor = UltraCircuitBuilder();
    auto c = fr::random_element();
    auto d = uint256_t(c).slice(0, 133);
    auto e = fr(d);
    auto a_idx = circuit_constructor.add_variable(fr(e));
    circuit_constructor.create_add_gate(
        { a_idx, circuit_constructor.zero_idx, circuit_constructor.zero_idx, 1, 0, 0, -fr(e) });
    circuit_constructor.decompose_into_default_range(a_idx, 134);

    bool result = CircuitChecker::check(circuit_constructor);
    EXPECT_EQ(result, true);
}

TEST(UltraCircuitConstructor, NonNativeFieldMultiplication)
{
    UltraCircuitBuilder circuit_constructor = UltraCircuitBuilder();

    fq a = fq::random_element();
    fq b = fq::random_element();
    uint256_t modulus = fq::modulus;

    uint1024_t a_big = uint512_t(uint256_t(a));
    uint1024_t b_big = uint512_t(uint256_t(b));
    uint1024_t p_big = uint512_t(uint256_t(modulus));

    uint1024_t q_big = (a_big * b_big) / p_big;
    uint1024_t r_big = (a_big * b_big) % p_big;

    uint256_t q(q_big.lo.lo);
    uint256_t r(r_big.lo.lo);

    const auto split_into_limbs = [&](const uint512_t& input) {
        constexpr size_t NUM_BITS = 68;
        std::array<fr, 5> limbs;
        limbs[0] = input.slice(0, NUM_BITS).lo;
        limbs[1] = input.slice(NUM_BITS * 1, NUM_BITS * 2).lo;
        limbs[2] = input.slice(NUM_BITS * 2, NUM_BITS * 3).lo;
        limbs[3] = input.slice(NUM_BITS * 3, NUM_BITS * 4).lo;
        limbs[4] = fr(input.lo);
        return limbs;
    };

    const auto get_limb_witness_indices = [&](const std::array<fr, 5>& limbs) {
        std::array<uint32_t, 5> limb_indices;
        limb_indices[0] = circuit_constructor.add_variable(limbs[0]);
        limb_indices[1] = circuit_constructor.add_variable(limbs[1]);
        limb_indices[2] = circuit_constructor.add_variable(limbs[2]);
        limb_indices[3] = circuit_constructor.add_variable(limbs[3]);
        limb_indices[4] = circuit_constructor.add_variable(limbs[4]);
        return limb_indices;
    };
    const uint512_t BINARY_BASIS_MODULUS = uint512_t(1) << (68 * 4);
    auto modulus_limbs = split_into_limbs(BINARY_BASIS_MODULUS - uint512_t(modulus));

    const auto a_indices = get_limb_witness_indices(split_into_limbs(uint256_t(a)));
    const auto b_indices = get_limb_witness_indices(split_into_limbs(uint256_t(b)));
    const auto q_indices = get_limb_witness_indices(split_into_limbs(uint256_t(q)));
    const auto r_indices = get_limb_witness_indices(split_into_limbs(uint256_t(r)));

    non_native_field_witnesses<fr> inputs{
        a_indices, b_indices, q_indices, r_indices, modulus_limbs, fr(uint256_t(modulus)),
    };
    const auto [lo_1_idx, hi_1_idx] = circuit_constructor.evaluate_non_native_field_multiplication(inputs);
    circuit_constructor.range_constrain_two_limbs(lo_1_idx, hi_1_idx, 70, 70);

    bool result = CircuitChecker::check(circuit_constructor);
    EXPECT_EQ(result, true);
}

/**
 * @brief Test that the aux block only contains aux gates.
 *
 */
TEST(UltraCircuitConstructor, NonNativeFieldMultiplicationSortCheck)
{
    UltraCircuitBuilder circuit_constructor = UltraCircuitBuilder();

    fq a = fq::random_element();
    fq b = fq::random_element();
    uint256_t modulus = fq::modulus;

    uint1024_t a_big = uint512_t(uint256_t(a));
    uint1024_t b_big = uint512_t(uint256_t(b));
    uint1024_t p_big = uint512_t(uint256_t(modulus));

    uint1024_t q_big = (a_big * b_big) / p_big;
    uint1024_t r_big = (a_big * b_big) % p_big;

    uint256_t q(q_big.lo.lo);
    uint256_t r(r_big.lo.lo);

    const auto split_into_limbs = [&](const uint512_t& input) {
        constexpr size_t NUM_BITS = 68;
        std::array<fr, 5> limbs;
        limbs[0] = input.slice(0, NUM_BITS).lo;
        limbs[1] = input.slice(NUM_BITS * 1, NUM_BITS * 2).lo;
        limbs[2] = input.slice(NUM_BITS * 2, NUM_BITS * 3).lo;
        limbs[3] = input.slice(NUM_BITS * 3, NUM_BITS * 4).lo;
        limbs[4] = fr(input.lo);
        return limbs;
    };

    const auto get_limb_witness_indices = [&](const std::array<fr, 5>& limbs) {
        std::array<uint32_t, 5> limb_indices;
        limb_indices[0] = circuit_constructor.add_variable(limbs[0]);
        limb_indices[1] = circuit_constructor.add_variable(limbs[1]);
        limb_indices[2] = circuit_constructor.add_variable(limbs[2]);
        limb_indices[3] = circuit_constructor.add_variable(limbs[3]);
        limb_indices[4] = circuit_constructor.add_variable(limbs[4]);
        return limb_indices;
    };
    const uint512_t BINARY_BASIS_MODULUS = uint512_t(1) << (68 * 4);
    auto modulus_limbs = split_into_limbs(BINARY_BASIS_MODULUS - uint512_t(modulus));

    const auto a_indices = get_limb_witness_indices(split_into_limbs(uint256_t(a)));
    const auto b_indices = get_limb_witness_indices(split_into_limbs(uint256_t(b)));
    const auto q_indices = get_limb_witness_indices(split_into_limbs(uint256_t(q)));
    const auto r_indices = get_limb_witness_indices(split_into_limbs(uint256_t(r)));

    non_native_field_witnesses<fr> inputs{
        a_indices, b_indices, q_indices, r_indices, modulus_limbs, fr(uint256_t(modulus)),
    };
    const auto [lo_1_idx, hi_1_idx] = circuit_constructor.evaluate_non_native_field_multiplication(inputs);
    circuit_constructor.range_constrain_two_limbs(lo_1_idx, hi_1_idx, 70, 70);

    bool result = CircuitChecker::check(circuit_constructor);
    EXPECT_EQ(result, true);

    // Everything above was copied from the previous test.
    // Check that in the aux blocks, the other selectors besides the aux selector are zero
    for (size_t i = 0; i < circuit_constructor.blocks.aux.size(); ++i) {
        EXPECT_EQ(circuit_constructor.blocks.aux.q_arith()[i], 0);
        EXPECT_EQ(circuit_constructor.blocks.aux.q_delta_range()[i], 0);
        EXPECT_EQ(circuit_constructor.blocks.aux.q_elliptic()[i], 0);
        EXPECT_EQ(circuit_constructor.blocks.aux.q_lookup_type()[i], 0);
        EXPECT_EQ(circuit_constructor.blocks.aux.q_poseidon2_external()[i], 0);
        EXPECT_EQ(circuit_constructor.blocks.aux.q_poseidon2_internal()[i], 0);
    }
}

TEST(UltraCircuitConstructor, Rom)
{
    UltraCircuitBuilder circuit_constructor = UltraCircuitBuilder();

    uint32_t rom_values[8]{
        circuit_constructor.add_variable(fr::random_element()), circuit_constructor.add_variable(fr::random_element()),
        circuit_constructor.add_variable(fr::random_element()), circuit_constructor.add_variable(fr::random_element()),
        circuit_constructor.add_variable(fr::random_element()), circuit_constructor.add_variable(fr::random_element()),
        circuit_constructor.add_variable(fr::random_element()), circuit_constructor.add_variable(fr::random_element()),
    };

    size_t rom_id = circuit_constructor.create_ROM_array(8);

    for (size_t i = 0; i < 8; ++i) {
        circuit_constructor.set_ROM_element(rom_id, i, rom_values[i]);
    }

    uint32_t a_idx = circuit_constructor.read_ROM_array(rom_id, circuit_constructor.add_variable(5));
    EXPECT_EQ(a_idx != rom_values[5], true);
    uint32_t b_idx = circuit_constructor.read_ROM_array(rom_id, circuit_constructor.add_variable(4));
    uint32_t c_idx = circuit_constructor.read_ROM_array(rom_id, circuit_constructor.add_variable(1));

    const auto d_value = circuit_constructor.get_variable(a_idx) + circuit_constructor.get_variable(b_idx) +
                         circuit_constructor.get_variable(c_idx);
    uint32_t d_idx = circuit_constructor.add_variable(d_value);

    circuit_constructor.create_big_add_gate({
        a_idx,
        b_idx,
        c_idx,
        d_idx,
        1,
        1,
        1,
        -1,
        0,
    });

    bool result = CircuitChecker::check(circuit_constructor);
    EXPECT_EQ(result, true);
}

/**
 * @brief A simple-as-possible RAM read test, for easier debugging
 *
 */
TEST(UltraCircuitConstructor, RamSimple)
{
    UltraCircuitBuilder builder;

    // Initialize a length 1 RAM array with a single value
    fr ram_value = 5;
    uint32_t ram_value_idx = builder.add_variable(ram_value);
    size_t ram_id = builder.create_RAM_array(/*array_size=*/1);
    builder.init_RAM_element(ram_id, /*index_value=*/0, ram_value_idx);

    // Read from the RAM array we just created (at the 0th index)
    uint32_t read_idx = builder.add_variable(0);
    uint32_t a_idx = builder.read_RAM_array(ram_id, read_idx);

    // Use the result in a simple arithmetic gate
    builder.create_big_add_gate({
        a_idx,
        builder.zero_idx,
        builder.zero_idx,
        builder.zero_idx,
        -1,
        0,
        0,
        0,
        builder.get_variable(ram_value_idx),
    });

    EXPECT_TRUE(CircuitChecker::check(builder));
}

TEST(UltraCircuitConstructor, Ram)
{
    UltraCircuitBuilder circuit_constructor = UltraCircuitBuilder();

    uint32_t ram_values[8]{
        circuit_constructor.add_variable(fr::random_element()), circuit_constructor.add_variable(fr::random_element()),
        circuit_constructor.add_variable(fr::random_element()), circuit_constructor.add_variable(fr::random_element()),
        circuit_constructor.add_variable(fr::random_element()), circuit_constructor.add_variable(fr::random_element()),
        circuit_constructor.add_variable(fr::random_element()), circuit_constructor.add_variable(fr::random_element()),
    };

    size_t ram_id = circuit_constructor.create_RAM_array(8);

    for (size_t i = 0; i < 8; ++i) {
        circuit_constructor.init_RAM_element(ram_id, i, ram_values[i]);
    }

    uint32_t a_idx = circuit_constructor.read_RAM_array(ram_id, circuit_constructor.add_variable(5));
    EXPECT_EQ(a_idx != ram_values[5], true);

    uint32_t b_idx = circuit_constructor.read_RAM_array(ram_id, circuit_constructor.add_variable(4));
    uint32_t c_idx = circuit_constructor.read_RAM_array(ram_id, circuit_constructor.add_variable(1));

    circuit_constructor.write_RAM_array(
        ram_id, circuit_constructor.add_variable(4), circuit_constructor.add_variable(500));
    uint32_t d_idx = circuit_constructor.read_RAM_array(ram_id, circuit_constructor.add_variable(4));

    EXPECT_EQ(circuit_constructor.get_variable(d_idx), 500);

    // ensure these vars get used in another arithmetic gate
    const auto e_value = circuit_constructor.get_variable(a_idx) + circuit_constructor.get_variable(b_idx) +
                         circuit_constructor.get_variable(c_idx) + circuit_constructor.get_variable(d_idx);
    uint32_t e_idx = circuit_constructor.add_variable(e_value);

    circuit_constructor.create_big_add_gate(
        {
            a_idx,
            b_idx,
            c_idx,
            d_idx,
            -1,
            -1,
            -1,
            -1,
            0,
        },
        true);
    circuit_constructor.create_big_add_gate(
        {
            circuit_constructor.zero_idx,
            circuit_constructor.zero_idx,
            circuit_constructor.zero_idx,
            e_idx,
            0,
            0,
            0,
            0,
            0,
        },
        false);

    bool result = CircuitChecker::check(circuit_constructor);
    EXPECT_EQ(result, true);

    // Test the builder copy constructor for a circuit with RAM gates
    UltraCircuitBuilder duplicate_circuit_constructor{ circuit_constructor };

    EXPECT_EQ(duplicate_circuit_constructor.get_estimated_num_finalized_gates(),
              circuit_constructor.get_estimated_num_finalized_gates());
    EXPECT_TRUE(CircuitChecker::check(duplicate_circuit_constructor));
}

TEST(UltraCircuitConstructor, RangeChecksOnDuplicates)
{
    UltraCircuitBuilder circuit_constructor = UltraCircuitBuilder();

    uint32_t a = circuit_constructor.add_variable(100);
    uint32_t b = circuit_constructor.add_variable(100);
    uint32_t c = circuit_constructor.add_variable(100);
    uint32_t d = circuit_constructor.add_variable(100);

    circuit_constructor.assert_equal(a, b);
    circuit_constructor.assert_equal(a, c);
    circuit_constructor.assert_equal(a, d);

    circuit_constructor.create_new_range_constraint(a, 1000);
    circuit_constructor.create_new_range_constraint(b, 1001);
    circuit_constructor.create_new_range_constraint(c, 999);
    circuit_constructor.create_new_range_constraint(d, 1000);

    circuit_constructor.create_big_add_gate(
        {
            a,
            b,
            c,
            d,
            0,
            0,
            0,
            0,
            0,
        },
        false);
    bool result = CircuitChecker::check(circuit_constructor);
    EXPECT_EQ(result, true);
}

TEST(UltraCircuitConstructor, CheckCircuitShowcase)
{
    UltraCircuitBuilder circuit_constructor = UltraCircuitBuilder();
    // check_circuit allows us to check correctness on the go

    uint32_t a = circuit_constructor.add_variable(0xdead);
    uint32_t b = circuit_constructor.add_variable(0xbeef);
    // Let's create 2 gates that will bind these 2 variables to be one these two values
    circuit_constructor.create_poly_gate(
        { a, a, circuit_constructor.zero_idx, fr(1), -fr(0xdead) - fr(0xbeef), 0, 0, fr(0xdead) * fr(0xbeef) });
    circuit_constructor.create_poly_gate(
        { b, b, circuit_constructor.zero_idx, fr(1), -fr(0xdead) - fr(0xbeef), 0, 0, fr(0xdead) * fr(0xbeef) });

    // We can check if this works
    EXPECT_EQ(CircuitChecker::check(circuit_constructor), true);

    // Now let's create a range constraint for b
    circuit_constructor.create_new_range_constraint(b, 0xbeef);

    // We can check if this works
    EXPECT_EQ(CircuitChecker::check(circuit_constructor), true);

    // But what if we now assert b to be equal to a?
    circuit_constructor.assert_equal(a, b, "Oh no");

    // It fails, because a is 0xdead and it can't fit in the range constraint
    EXPECT_EQ(CircuitChecker::check(circuit_constructor), false);

    // But if we force them both back to be 0xbeef...
    uint32_t c = circuit_constructor.add_variable(0xbeef);
    circuit_constructor.assert_equal(c, b);

    // The circuit will magically pass again
    EXPECT_EQ(CircuitChecker::check(circuit_constructor), true);
}

} // namespace bb