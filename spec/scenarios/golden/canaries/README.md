# Canary rows

Rows engineered to **fail**. `harness_spec.rb` runs each one and asserts it does.

They are the part of the suite that survives someone — or something — editing the harness. A lint can
be weakened, a comparison can be loosened, an assertion can be made to skip a field; each of those
changes looks locally reasonable and none of them breaks a green row. All of them make a canary pass,
and a passing canary fails the build.

One canary per mechanism, each documenting the mechanism it guards. If you add an assertion kind to
the interpreter, add a canary for it in the same change — an assertion nobody has ever seen fail is
indistinguishable from one that cannot fail.

These files are NOT part of the matrix: `GoldenMatrix.matrix_files` globs `matrix/*.yml` only, so
canaries never reach the ledger, the census or the coverage number.
