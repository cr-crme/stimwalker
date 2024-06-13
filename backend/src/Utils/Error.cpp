#define STIMWALKER_API_EXPORTS
#include "Utils/Error.h"

using namespace STIMWALKER_NAMESPACE;

void utils::Error::raise(
    const utils::String &message)
{
    throw std::runtime_error(message);
}

void utils::Error::check(
    bool cond,
    const utils::String& message)
{
    if (!cond) {
        throw std::runtime_error(message);
    }

}

void utils::Error::warning(
    bool cond,
    const utils::String& message)
{
    if (!cond) {
        std::cout << "Warning: " << message << std::endl;
    }
}
