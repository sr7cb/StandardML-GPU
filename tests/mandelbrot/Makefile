MLTONFLAGS = -default-ann 'allowFFI true' -default-ann 'allowLineComments true' -link-opt \
						 '-rdynamic -L/usr/local/cuda-11.7/lib64/ -lcudart -lstdc++'
LIBPATH = ../../lib/
BLOB = $(LIBPATH)/gpublob.o

mandel : mandel.sml $(BLOB)
	mlton $(MLTONFLAGS) mandel.mlb ../../lib/gpublob.o
$(LIBPATH)/gpublob.o :
	(cd ../../lib/;make)

clean : 
	rm mandel
