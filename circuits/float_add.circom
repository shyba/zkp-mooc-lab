pragma circom 2.0.0;

/////////////////////////////////////////////////////////////////////////////////////
/////////////////////// Templates from the circomlib ////////////////////////////////
////////////////// Copy-pasted here for easy reference //////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////

/*
 * Outputs `a` AND `b`
 */
template AND() {
    signal input a;
    signal input b;
    signal output out;

    out <== a*b;
}

/*
 * Outputs `a` OR `b`
 */
template OR() {
    signal input a;
    signal input b;
    signal output out;

    out <== a + b - a*b;
}

/*
 * `out` = `cond` ? `L` : `R`
 */
template IfThenElse() {
    signal input cond;
    signal input L;
    signal input R;
    signal output out;

    out <== cond * (L - R) + R;
}

/*
 * (`outL`, `outR`) = `sel` ? (`R`, `L`) : (`L`, `R`)
 */
template Switcher() {
    signal input sel;
    signal input L;
    signal input R;
    signal output outL;
    signal output outR;

    signal aux;

    aux <== (R-L)*sel;
    outL <==  aux + L;
    outR <== -aux + R;
}

/*
 * Decomposes `in` into `b` bits, given by `bits`.
 * Least significant bit in `bits[0]`.
 * Enforces that `in` is at most `b` bits long.
 */
template Num2Bits(b) {
    signal input in;
    signal output bits[b];

    for (var i = 0; i < b; i++) {
        bits[i] <-- (in >> i) & 1;
        bits[i] * (1 - bits[i]) === 0;
    }
    var sum_of_bits = 0;
    for (var i = 0; i < b; i++) {
        sum_of_bits += (2 ** i) * bits[i];
    }
    sum_of_bits === in;
}

/*
 * Reconstructs `out` from `b` bits, given by `bits`.
 * Least significant bit in `bits[0]`.
 */
template Bits2Num(b) {
    signal input bits[b];
    signal output out;
    var lc = 0;

    for (var i = 0; i < b; i++) {
        lc += (bits[i] * (1 << i));
    }
    out <== lc;
}

/*
 * Checks if `in` is zero and returns the output in `out`.
 */
template IsZero() {
    signal input in;
    signal output out;

    signal inv;

    inv <-- in!=0 ? 1/in : 0;

    out <== -in*inv +1;
    in*out === 0;
}

/*
 * Checks if `in[0]` == `in[1]` and returns the output in `out`.
 */
template IsEqual() {
    signal input in[2];
    signal output out;

    component isz = IsZero();

    in[1] - in[0] ==> isz.in;

    isz.out ==> out;
}

/*
 * Checks if `in[0]` < `in[1]` and returns the output in `out`.
 * Assumes `n` bit inputs. The behavior is not well-defined if any input is more than `n`-bits long.
 */
template LessThan(n) {
    assert(n <= 252);
    signal input in[2];
    signal output out;

    component n2b = Num2Bits(n+1);

    n2b.in <== in[0]+ (1<<n) - in[1];

    out <== 1-n2b.bits[n];
}

/////////////////////////////////////////////////////////////////////////////////////
///////////////////////// Templates for this lab ////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////

/*
 * Outputs `out` = 1 if `in` is at most `b` bits long, and 0 otherwise.
 */
template CheckBitLength(b) {
    assert(b < 254);
    signal input in;
    signal output out;

    var sum_of_bits = 0;
    signal bit[b];
    for (var i = 0; i < b; i++) {
        bit[i] <-- (in >> i) & 1;
        bit[i] * (1 - bit[i]) === 0;
        sum_of_bits += (2 ** i) * bit[i];
    }
    component eq = IsEqual();
    eq.in[0] <== in;
    eq.in[1] <-- sum_of_bits;
    out <== eq.out;
    component check = IsEqual();
    check.in[0] <-- out*in;
    check.in[1] <-- out*sum_of_bits;
    check.out === 1;
}

/*
 * Enforces the well-formedness of an exponent-mantissa pair (e, m), which is defined as follows:
 * if `e` is zero, then `m` must be zero
 * else, `e` must be at most `k` bits long, and `m` must be in the range [2^p, 2^p+1)
 */
template CheckWellFormedness(k, p) {
    signal input e;
    signal input m;

    // check if `e` is zero
    component is_e_zero = IsZero();
    is_e_zero.in <== e;

    // Case I: `e` is zero
    //// `m` must be zero
    component is_m_zero = IsZero();
    is_m_zero.in <== m;

    // Case II: `e` is nonzero
    //// `e` is `k` bits
    component check_e_bits = CheckBitLength(k);
    check_e_bits.in <== e;
    //// `m` is `p`+1 bits with the MSB equal to 1
    //// equivalent to check `m` - 2^`p` is in `p` bits
    component check_m_bits = CheckBitLength(p);
    check_m_bits.in <== m - (1 << p);

    // choose the right checks based on `is_e_zero`
    component if_else = IfThenElse();
    if_else.cond <== is_e_zero.out;
    if_else.L <== is_m_zero.out;
    //// check_m_bits.out * check_e_bits.out is equivalent to check_m_bits.out AND check_e_bits.out
    if_else.R <== check_m_bits.out * check_e_bits.out;

    // assert that those checks passed
    if_else.out === 1;
}

/*
 * Right-shifts `b`-bit long `x` by `shift` bits to output `y`, where `shift` is a public circuit parameter.
 */
template RightShift(b, shift) {
    assert(shift < b);
    signal input x;
    signal output y;

    var out;
    var shift_width = b - shift;
    component binary = Num2Bits(b);
    binary.in <== x;
    for(var i=0; i<shift_width; i++) {
        out += (binary.bits[shift+i] * (1 << i));
    }
    y <-- out;
}

/*
 * Rounds the input floating-point number and checks to ensure that rounding does not make the mantissa unnormalized.
 * Rounding is necessary to prevent the bitlength of the mantissa from growing with each successive operation.
 * The input is a normalized floating-point number (e, m) with precision `P`, where `e` is a `k`-bit exponent and `m` is a `P`+1-bit mantissa.
 * The output is a normalized floating-point number (e_out, m_out) representing the same value with a lower precision `p`.
 */
template RoundAndCheck(k, p, P) {
    signal input e;
    signal input m;
    signal output e_out;
    signal output m_out;
    assert(P > p);

    // check if no overflow occurs
    component if_no_overflow = LessThan(P+1);
    if_no_overflow.in[0] <== m;
    if_no_overflow.in[1] <== (1 << (P+1)) - (1 << (P-p-1));
    signal no_overflow <== if_no_overflow.out;

    var round_amt = P-p;
    // Case I: no overflow
    // compute (m + 2^{round_amt-1}) >> round_amt
    var m_prime = m + (1 << (round_amt-1));
    //// Although m_prime is P+1 bits long in no overflow case, it can be P+2 bits long
    //// in the overflow case and the constraints should not fail in either case
    component right_shift = RightShift(P+2, round_amt);
    right_shift.x <== m_prime;
    var m_out_1 = right_shift.y;
    var e_out_1 = e;

    // Case II: overflow
    var e_out_2 = e + 1;
    var m_out_2 = (1 << p);

    // select right output based on no_overflow
    component if_else[2];
    for (var i = 0; i < 2; i++) {
        if_else[i] = IfThenElse();
        if_else[i].cond <== no_overflow;
    }
    if_else[0].L <== e_out_1;
    if_else[0].R <== e_out_2;
    if_else[1].L <== m_out_1;
    if_else[1].R <== m_out_2;
    e_out <== if_else[0].out;
    m_out <== if_else[1].out;
}

/*
 * Left-shifts `x` by `shift` bits to output `y`.
 * Enforces 0 <= `shift` < `shift_bound`.
 * If `skip_checks` = 1, then we don't care about the output and the `shift_bound` constraint is not enforced.
 */
template LeftShift(shift_bound) {
    signal input x;
    signal input shift;
    signal input skip_checks;
    signal output y;

    component less_than_bound = LessThan(252);
    less_than_bound.in[0] <== (1-skip_checks) * shift;
    less_than_bound.in[1] <== shift_bound;
    less_than_bound.out === 1;

    component zero_is_less = LessThan(252);
    component is_zero = IsZero();
    component either = OR();
    zero_is_less.in[0] <== 0;
    zero_is_less.in[1] <== shift_bound;
    is_zero.in <== shift;
    either.a <== is_zero.out;
    either.b <== zero_is_less.out;
    either.out === 1;

    y <-- x * (2 ** shift);
}

/*
 * Find the Most-Significant Non-Zero Bit (MSNZB) of `in`, where `in` is assumed to be non-zero value of `b` bits.
 * Outputs the MSNZB as a one-hot vector `one_hot` of `b` bits, where `one_hot`[i] = 1 if MSNZB(`in`) = i and 0 otherwise.
 * The MSNZB is output as a one-hot vector to reduce the number of constraints in the subsequent `Normalize` template.
 * Enforces that `in` is non-zero as MSNZB(0) is undefined.
 * If `skip_checks` = 1, then we don't care about the output and the non-zero constraint is not enforced.
 */
template MSNZB(b) {
    signal input in;
    signal input skip_checks;
    signal output one_hot[b];

    component zero_less_than = LessThan(b);
    component or_ignore = OR();
    zero_less_than.in[0] <== 0;
    zero_less_than.in[1] <== in;
    or_ignore.a <== zero_less_than.out;
    or_ignore.b <== skip_checks;
    or_ignore.out === 1;

    component binary = Num2Bits(b);
    binary.in <== in;

    component less_than_max[b];
    component less_than[b];
    component and[b];
    for(var i=0; i<b; i++){
        less_than_max[i] = LessThan(b);
        less_than_max[i].in[0] <== in;
        less_than_max[i].in[1] <== 2 ** (i+1);
        less_than[i] = LessThan(b);
        less_than[i].in[0] <== (2 ** i) - 1;
        less_than[i].in[1] <== in;
        and[i] = AND();
        and[i].a <== less_than_max[i].out;
        and[i].b <== less_than[i].out;
        one_hot[i] <== and[i].out;
    }

}

/*
 * Normalizes the input floating-point number.
 * The input is a floating-point number with a `k`-bit exponent `e` and a `P`+1-bit *unnormalized* mantissa `m` with precision `p`, where `m` is assumed to be non-zero.
 * The output is a floating-point number representing the same value with exponent `e_out` and a *normalized* mantissa `m_out` of `P`+1-bits and precision `P`.
 * Enforces that `m` is non-zero as a zero-value can not be normalized.
 * If `skip_checks` = 1, then we don't care about the output and the non-zero constraint is not enforced.
 */
template Normalize(k, p, P) {
    signal input e;
    signal input m;
    signal input skip_checks;
    signal output e_out;
    signal output m_out;
    assert(P > p);
    //ell = msnzb(m, P+1)
    //m <<= (P - ell)
    //e = e + ell - p
    //return (e, m)

    component msn = MSNZB(P+1);
    msn.in <== m;
    msn.skip_checks <== skip_checks;

    var ell = 0;

    for (var i = 0; i <= P; i++) {
        ell += msn.one_hot[i]*i;
    }

    e_out <== e + ell - p;
    m_out <-- m << (P - ell);
}

/*
 * Adds two floating-point numbers.
 * The inputs are normalized floating-point numbers with `k`-bit exponents `e` and `p`+1-bit mantissas `m` with scale `p`.
 * Does not assume that the inputs are well-formed and makes appropriate checks for the same.
 * The output is a normalized floating-point number with exponent `e_out` and mantissa `m_out` of `p`+1-bits and scale `p`.
 * Enforces that inputs are well-formed.
 */
template FloatAdd(k, p) {
    signal input e[2];
    signal input m[2];
    signal output e_out;
    signal output m_out;

    //''' check that the inputs are well-formed '''
    //check_well_formedness(k, p, e_1, m_1)
    //check_well_formedness(k, p, e_2, m_2)
    component check_well_formedness[2];

    for (var i = 0; i < 2; i++) {
        check_well_formedness[i] = CheckWellFormedness(k, p);
        check_well_formedness[i].e <== e[i];
        check_well_formedness[i].m <== m[i];
    }

    //''' Arrange numbers in the order of their magnitude.
    //    Although not the same as magnitude, note that comparing e_1 || m_1 against e_2 || m_2 suffices to compare magnitudes.
    //'''

    //''' comparison over k+p+1 bits '''
    component mgn_one_less_than_mgn_two = LessThan(k+p+1);
    //mgn_1 = (e_1 << (p+1)) + m_1
    //mgn_2 = (e_2 << (p+1)) + m_2
    mgn_one_less_than_mgn_two.in[0] <== (e[0] * (1<<(p+1))) + m[0];
    mgn_one_less_than_mgn_two.in[1] <== (e[1] * (1<<(p+1))) + m[1];

    //if mgn_1 > mgn_2:
    //    (alpha_e, alpha_m) = (e_1, m_1)
    //    (beta_e, beta_m) = (e_2, m_2)
    //else:
    //    (alpha_e, alpha_m) = (e_2, m_2)
    //    (beta_e, beta_m) = (e_1, m_1)
    component first_column = Switcher();
    component second_column = Switcher();

    first_column.sel <== mgn_one_less_than_mgn_two.out;
    first_column.L <== e[0];
    first_column.R <== e[1];

    second_column.sel <== mgn_one_less_than_mgn_two.out;
    second_column.L <== m[0];
    second_column.R <== m[1];

    var alpha_e = first_column.outL;
    var beta_e = first_column.outR;
    var alpha_m = second_column.outL;
    var beta_m = second_column.outR;

    //diff = alpha_e - beta_e
    signal diff <== alpha_e - beta_e;

    //if diff > p + 1 or alpha_e == 0:
    component p_less_than_diff = LessThan(k);
    p_less_than_diff.in[0] <== p+1;
    p_less_than_diff.in[1] <== diff;

    component alpha_is_zero = IsZero();
    alpha_is_zero.in <== alpha_e;

    // or alpha e == 0
    component p_is_less_or_alpha_is_zero = OR();
    p_is_less_or_alpha_is_zero.a <== p_less_than_diff.out;
    p_is_less_or_alpha_is_zero.b <== alpha_is_zero.out;

    component alpha_branch = IfThenElse();
    alpha_branch.cond <== p_is_less_or_alpha_is_zero.out;
    alpha_branch.L <== 1;
    alpha_branch.R <== alpha_m;

    //alpha_m <<= diff
    //''' m fits in 2*p+2 bits '''
    //m = alpha_m + beta_m
    //e = beta_e
    //(normalized_e, normalized_m) = normalize(k, p, 2*p+1, e, m)
    //(e_out, m_out) = round_nearest_and_check(k, p, 2*p+1, normalized_e, normalized_m)

    component if_else_diff = IfThenElse();
    if_else_diff.cond <== p_is_less_or_alpha_is_zero.out;
    if_else_diff.L <== 0;
    if_else_diff.R <== diff;

    component if_else_beta_e = IfThenElse();
    if_else_beta_e.cond <== p_is_less_or_alpha_is_zero.out;
    if_else_beta_e.L <== 1;
    if_else_beta_e.R <== beta_e;

    component m_alpha_left_shift = LeftShift(p+2);
    m_alpha_left_shift.x <== alpha_branch.out;
    m_alpha_left_shift.shift <== if_else_diff.out;
    m_alpha_left_shift.skip_checks <== 0;

    //(normalized_e, normalized_m) = normalize(k, p, 2*p+1, e, m)
    component normalize = Normalize(k, p, 2*p+1);
    normalize.e <== if_else_beta_e.out;
    normalize.m <== m_alpha_left_shift.y + beta_m;
    normalize.skip_checks <== 0;

    //(e_out, m_out) = round_nearest_and_check(k, p, 2*p+1, normalized_e, normalized_m)
    component round_to_nearest_and_check = RoundAndCheck(k, p, 2*p+1);
    round_to_nearest_and_check.e <== normalize.e_out;
    round_to_nearest_and_check.m <== normalize.m_out;


    component if_else_m = IfThenElse();
    if_else_m.cond <== p_is_less_or_alpha_is_zero.out;
    if_else_m.L <== alpha_m;
    if_else_m.R <== round_to_nearest_and_check.m_out;

    component if_else_e = IfThenElse();
    if_else_e.cond <== p_is_less_or_alpha_is_zero.out;
    if_else_e.L <== alpha_e;
    if_else_e.R <== round_to_nearest_and_check.e_out;

    e_out <== if_else_e.out;
    m_out <== if_else_m.out;
}
