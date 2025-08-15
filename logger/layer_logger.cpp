#include "layer_logger.h"
#include <cstdio>

LayerLogger::LayerLogger(FCLLayer *layer, const char *fileName) : Logger(fileName), layer(layer) {}