

SOURCES = breakpad_qcawrapper.cpp
OBJECTS = $(SOURCES:.cpp=.o)
SHAREDOBJECT = libbreakpad_qcawrapper.so

all : $(SOURCES) $(SHAREDOBJECT)

$(SHAREDOBJECT): $(OBJECTS)
	$(CXX) -o $@ -shared $(LDFLAGS) $(OBJECTS) -Wl,--whole-archive -lbreakpad_client -Wl,--no-whole-archive

.cpp.o:
	$(CXX) -c -std=c++11 $(CXXFLAGS) $< -o $@

clean:
	$(RM) *.o *.so*
