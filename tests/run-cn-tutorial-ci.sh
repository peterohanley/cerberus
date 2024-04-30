#!/bin/bash


TUTORIAL_PATH=$1

if [ -n "$TUTORIAL_PATH" ] 
then
    echo "using tutorial path $TUTORIAL_PATH"
else
    echo "missing argument for CN tutorial path"
    exit 1
fi



# copying from run-ci.sh
export DYLD_LIBRARY_PATH=$DYLD_LIBRARY_PATH:`ocamlfind query z3`
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:`ocamlfind query z3`
CN=$OPAM_SWITCH_PREFIX/bin/cn

HERE=$(pwd)

cd "$TUTORIAL_PATH"/src/example-archive/



cd dafny-tutorial
/bin/bash ../check.sh $CN
if [ $? != 0 ] 
then
   exit 1
fi
cd ..

cd SAW
/bin/bash ../check.sh $CN
if [ $? != 0 ] 
then
   exit 1
fi
cd ..

cd c-testsuite
/bin/bash ../check.sh $CN
if [ $? != 0 ] 
then
   exit 1
fi
cd ..

cd simple-examples
/bin/bash ../check.sh $CN
if [ $? != 0 ] 
then
   exit 1
fi
cd ..

cd $HERE


