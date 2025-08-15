#include "logger.h"

Logger::Logger(const char *fileName)
{
    logFile = fopen(fileName, "wt");
}

void Logger::log()
{
    return;
}