#ifndef CONFIG_H
#define CONFIG_H

#include <stdint.h>

namespace Config {

/**
 * Get the persisted device ID, generating and saving one if it does not exist.
 */
uint32_t getOrGenerateId();

}  // namespace Config

#endif  // CONFIG_H
