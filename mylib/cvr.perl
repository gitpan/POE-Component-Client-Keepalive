# $Id: cvr.perl,v 1.1.1.1 2004/10/03 16:50:29 rcaputo Exp $

# Be warned: Pod::Coverage will add a lot of time to the tests.
# Before: Files=8, Tests=51, 74 wallclock secs (...)
# After : Files=8, Tests=51, 459 wallclock secs (...)

cover -delete
HARNESS_PERL_SWITCHES="-MDevel::Cover=+ignore,mylib,-coverage,statement,branch,subroutine,time,condition,path" make test
cover
