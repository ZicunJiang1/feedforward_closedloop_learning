#include <chrono>
#include <cstdlib>
#include <iostream>
#include <random>
#include <string>

#include <cerrno>
#include <cstring>
#include <sys/stat.h>
#include <sys/types.h>

namespace {

bool createDirectory(const std::string& path)
{
    if (mkdir(path.c_str(), 0755) == 0) {
        return true;
    }

    if (errno == EEXIST) {
        return true;
    }

    std::cerr
        << "Failed to create directory "
        << path
        << ": "
        << std::strerror(errno)
        << '\n';

    return false;
}

int generateSeed()
{
    const auto timeValue =
        std::chrono::high_resolution_clock::now()
            .time_since_epoch()
            .count();

    std::mt19937 generator(
        static_cast<unsigned int>(timeValue));

    std::uniform_int_distribution<int> distribution(1, 100);

    return distribution(generator);
}

} // namespace

int main()
{
    const int seed = generateSeed();

    const std::string fclDirectory = "DataFCL";
    const std::string cldlDirectory = "DataDL";

    if (!createDirectory(fclDirectory) ||
        !createDirectory(cldlDirectory)) {
        return 1;
    }

    std::cout
        << "====================================\n"
        << "FCL vs CLDL experiment\n"
        << "Random seed: "
        << seed
        << "\n====================================\n";

    const std::string fclCommand =
        "./linefollower/linefollower 0 " +
        std::to_string(seed) +
        " " +
        fclDirectory;

    std::cout
        << "\nStarting FCL run...\n"
        << fclCommand
        << '\n';

    const int fclStatus =
        std::system(fclCommand.c_str());

    if (fclStatus != 0) {
        std::cerr
            << "FCL run failed with status "
            << fclStatus
            << '\n';
        return 2;
    }

    std::cout
        << "\nFCL run completed.\n"
        << "Starting CLDL run...\n";

    const std::string cldlCommand =
        "./cldl/linefollowercldl 0 " +
        std::to_string(seed) +
        " " +
        cldlDirectory;

    std::cout << cldlCommand << '\n';

    const int cldlStatus =
        std::system(cldlCommand.c_str());

    if (cldlStatus != 0) {
        std::cerr
            << "CLDL run failed with status "
            << cldlStatus
            << '\n';
        return 3;
    }

    std::cout
        << "\nBoth runs completed successfully.\n"
        << "Seed: "
        << seed
        << '\n'
        << "FCL data: "
        << fclDirectory
        << '\n'
        << "CLDL data: "
        << cldlDirectory
        << '\n';

    return 0;
}