#ifndef LOGGER_H
#define LOGGER_H

#include <cstdio>

class Logger
{
public:
    Logger(const char *fileName);
    virtual void log();

protected:
    FILE *logFile;
};

#endif