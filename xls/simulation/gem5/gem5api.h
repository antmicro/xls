#ifndef XLS_SIMULATION_GEM5_GEM5API_H_
#define XLS_SIMULATION_GEM5_GEM5API_H_

#include <stddef.h>
#include <stdint.h>

#define GEM5CC __attribute__((sysv_abi))

//!
//! \brief Error reporting callback. A simulator can provide a hook to be called
//!        In case an error occurs on the XLS side.
//!
struct C_ErrorOps {
  void* ctx;
  //!
  //! \brief Reports an error. `ctx` is passed as the first argument.
  //!
  void(GEM5CC* reportError)(void*, uint8_t severity, const char* message);
};

typedef void* C_XlsPeripheralH;

//!
//! \brief Callbacks for DMA transfer request responses. Those are generated per
//!        memory transfer request and given to the simulator as a part of the
//!        request procedure. Once the simulator is done processing the memory
//!        request it should use the callback to inform XLS that the transfer
//!        has finished.
//!
struct C_DmaResponseOps {
  //!
  //! \brief Callback's context
  //! \warning Context needs to remain valid for the entire duration of the
  //!          the transfer and can be freed only after the callback executes.
  //!
  void* ctx;
  //!
  //! \brief Informs XLS that the transfer has been completed and data has been
  //!        moved into/out of the buffer.
  //!
  void(GEM5CC* transfer_complete)(void* ctx);
};

//!
//! \brief Definition of the interface for making requests to Gem5.
//!        XLS should hold a single instance of that interface which should be
//!        initialized with `xls_initCallbacks` by Gem5.
//!
struct C_XlsCallbacks {
  //!
  //! \brief Simulation context. Should be valid through the entire simulation
  //!        since `xls_initCallbacks` is called.
  //!
  void* ctx;
  //!
  //! \brief Request a memory transfer from a simulated system's memory
  //!        To XLS's internal buffer.
  //! \param ctx pointer to this->ctx
  //! \param addr address at which the data to be transferred starts
  //! \param count number of contiguous bytes to be transffered starting from
  //!              `addr`.
  //! \param buf buffer to which the data should be written.
  //! \param response_ops callback for informing that the transfer has been
  //!        finished.
  //! \return zero on success, non-zero on error
  //!
  int(GEM5CC* xls_dmaMemToDev)(void* ctx, size_t addr, size_t count,
                               uint8_t* buf, C_DmaResponseOps response_ops);
  //!
  //! \brief Request a memory transfer from a XLS's internal buffer to
  //!        simulated system's memory.
  //! \param ctx pointer to this->ctx
  //! \param addr address at the memory range to which the data should be
  //!             written to starts.
  //! \param count number of contiguous bytes to be transffered starting from
  //!              `addr`.
  //! \param buf buffer from which the data should be read.
  //! \param response_ops callback for informing that the transfer has been
  //!        finished.
  //! \return zero on success, non-zero on error
  //!
  int(GEM5CC* xls_dmaDevToMem)(void* ctx, size_t addr, size_t count,
                               const uint8_t* buf,
                               C_DmaResponseOps response_ops);
  //!
  //! \brief Request a change of level on device's interrupt line.
  //! \param ctx pointer to this->ctx
  //! \param num Interrupt request number
  //! \param state level - false => low, true => high
  //! \return zero on success, non-zero on error
  //!
  int(GEM5CC* xls_requestIRQ)(void* ctx, size_t num, int state);
  //!
  //! \brief Log a message to simulator's output
  //! \param ctx pointer to this->ctx
  //! \param severity log severity:
  //!                 0 => INFO,
  //!                 1 => WARN,
  //!                 2 => ERROR,
  //! \param message log message
  //!
  void(GEM5CC* xls_log)(void* ctx, int severity, const char* message);
};

//!
//! \brief Initialize the interface to Gem5.
//! \param callbacks callbacks to use
//! \return zero on success, non-zero on error
//!
extern "C" int GEM5CC xls_initCallbacks(C_XlsCallbacks callbacks);

//!
//! \brief Instantiate a n XLS peripheral configured with .textproto config
//! \param config path to a a .textproto file with peripheral configuration
//! \param error_ops error reporting callback
//! \return A pointer to the created peripheral. NULL on failure.
//!
extern "C" C_XlsPeripheralH GEM5CC xls_setupPeripheral(const char* config,
                                                       C_ErrorOps* error_ops);

//!
//! \brief (Re)initialize an XLS peripheral
//! \param peripheral pointer to the XLS peripheral
//! \param error_ops error reporting callback
//! \return zero on success, non-zero on error
//!
extern "C" int GEM5CC xls_resetPeripheral(C_XlsPeripheralH peripheral,
                                          C_ErrorOps* error_ops);

//!
//! \brief Destroy an XLS peripheral
//! \param peripheral ppointer to the XLS peripheral
//! \param error_ops error reporting callback
//!
extern "C" void GEM5CC xls_destroyPeripheral(C_XlsPeripheralH peripheral,
                                             C_ErrorOps* error_ops);

//!
//! \brief Get the number of bytes reserved for peripheral's memory-mapped
//!        access.
//! \warning The peripheral needs to be initialized first with
//!          `xls_resetPeripheral`.
//! \param peripheral pointer to the XLS peripheral
//! \param error_ops error reporting callback
//! \return Number of bytes over which the peripheral's registers span.
//!
extern "C" size_t GEM5CC xls_getPeripheralSize(C_XlsPeripheralH peripheral,
                                               C_ErrorOps* error_ops);

//!
//! \brief perform one simulation step for the XLS peripheral
//! \param peripheral pointer to the XLS peripheral
//! \param error_ops error reporting callback
//!
extern "C" int GEM5CC xls_updatePeripheral(C_XlsPeripheralH peripheral,
                                           C_ErrorOps* error_ops);

//!
//! \brief Read a single BYTE from the peripheral's register.
//! \warning This will trigger a simulation update step
//! \param peripheral pointer to the XLS peripheral
//! \param address address of the register relative to the peripheral's
//!                base address. Can be in a middle/end of the register if
//!                the intention is to read at an offset.
//! \param buf pointer to a variable in which the read value should be stored.
//! \param error_ops error reporting callback
//! \return zero on success, non-zero on error
//!
extern "C" int GEM5CC xls_readByte(C_XlsPeripheralH peripheral,
                                   uint64_t address, uint8_t* buf,
                                   C_ErrorOps* error_ops);

//!
//! \brief Read a WORD (two bytes) from the peripheral's register.
//! \warning This will trigger a simulation update step
//! \param peripheral pointer to the XLS peripheral
//! \param address address of the register relative to the peripheral's
//!                base address. Can be in a middle/end of the register if
//!                the intention is to read at an offset.
//! \param buf pointer to a variable in which the read value should be stored.
//! \param error_ops error reporting callback
//! \return zero on success, non-zero on error
//!
extern "C" int GEM5CC xls_readWord(C_XlsPeripheralH peripheral,
                                   uint64_t address, uint16_t* buf,
                                   C_ErrorOps* error_ops);

//!
//! \brief Read a DOUBLE WORD (four bytes) from the peripheral's register.
//! \warning This will trigger a simulation update step
//! \param peripheral pointer to the XLS peripheral
//! \param address address of the register relative to the peripheral's
//!                base address. Can be in a middle/end of the register if
//!                the intention is to read at an offset.
//! \param buf pointer to a variable in which the read value should be stored.
//! \param error_ops error reporting callback
//! \return zero on success, non-zero on error
//!
extern "C" int GEM5CC xls_readDWord(C_XlsPeripheralH peripheral,
                                    uint64_t address, uint32_t* buf,
                                    C_ErrorOps* error_ops);

//!
//! \brief Read a QUAD WORD (eight bytes) from the peripheral's register.
//! \warning This will trigger a simulation update step
//! \param peripheral pointer to the XLS peripheral
//! \param address address of the register relative to the peripheral's
//!                base address. Can be in a middle/end of the register if
//!                the intention is to read at an offset.
//! \param buf pointer to a variable in which the read value should be stored.
//! \param error_ops error reporting callback
//! \return zero on success, non-zero on error
//!
extern "C" int GEM5CC xls_readQWord(C_XlsPeripheralH peripheral,
                                    uint64_t address, uint64_t* buf,
                                    C_ErrorOps* error_ops);

//!
//! \brief Write a single BYTE to the peripheral's register.
//! \warning This will trigger a simulation update step
//! \param peripheral pointer to the XLS peripheral
//! \param address address of the register relative to the peripheral's
//!                base address. Can be in a middle/end of the register if
//!                the intention is to write at an offset.
//! \param buf value to be written to the register
//! \param error_ops error reporting callback
//! \return zero on success, non-zero on error
//!
extern "C" int GEM5CC xls_writeByte(C_XlsPeripheralH peripheral_h,
                                    uint64_t address, uint8_t buf,
                                    C_ErrorOps* error_ops);

//!
//! \brief Write a WORD (two bytes) to the peripheral's register.
//! \warning This will trigger a simulation update step
//! \param peripheral pointer to the XLS peripheral
//! \param address address of the register relative to the peripheral's
//!                base address. Can be in a middle/end of the register if
//!                the intention is to write at an offset.
//! \param buf value to be written to the register
//! \param error_ops error reporting callback
//! \return zero on success, non-zero on error
//!
extern "C" int GEM5CC xls_writeWord(C_XlsPeripheralH peripheral_h,
                                    uint64_t address, uint16_t buf,
                                    C_ErrorOps* error_ops);

//!
//! \brief Write a DOUBLE WORD (four bytes) to the peripheral's register.
//! \warning This will trigger a simulation update step
//! \param peripheral pointer to the XLS peripheral
//! \param address address of the register relative to the peripheral's
//!                base address. Can be in a middle/end of the register if
//!                the intention is to write at an offset.
//! \param buf value to be written to the register
//! \param error_ops error reporting callback
//! \return zero on success, non-zero on error
//!
extern "C" int GEM5CC xls_writeDWord(C_XlsPeripheralH peripheral_h,
                                     uint64_t address, uint32_t buf,
                                     C_ErrorOps* error_ops);

//!
//! \brief Write a QUAD WORD (eight bytes) to the peripheral's register.
//! \warning This will trigger a simulation update step
//! \param peripheral pointer to the XLS peripheral
//! \param address address of the register relative to the peripheral's
//!                base address. Can be in a middle/end of the register if
//!                the intention is to write at an offset.
//! \param buf value to be written to the register
//! \param error_ops error reporting callback
//! \return zero on success, non-zero on error
//!
extern "C" int GEM5CC xls_writeQWord(C_XlsPeripheralH peripheral_h,
                                     uint64_t address, uint64_t buf,
                                     C_ErrorOps* error_ops);

#endif  // XLS_SIMULATION_GEM5_GEM5API_H_
