#ifndef __STIMWALKER_DATA_FIXED_TIME_SERIES_H__
#define __STIMWALKER_DATA_FIXED_TIME_SERIES_H__

#include "stimwalkerConfig.h"

#include "Data/TimeSeries.h"

namespace STIMWALKER_NAMESPACE::data {

/// @brief Class to store data
class FixedTimeSeries : public TimeSeries {
public:
  /// @brief Constructor
  /// @param deltaTime The time frequency of the data
  FixedTimeSeries(const std::chrono::microseconds &deltaTime);

  /// @brief Constructor
  /// @param startingTime The timestamp of the first data point
  /// @param deltaTime The time frequency of the data
  FixedTimeSeries(const std::chrono::system_clock::time_point &startingTime,
                  const std::chrono::microseconds &deltaTime);

  ~FixedTimeSeries() = default;

  /// @brief Add new data to the collection with the timestamp set to
  /// StartingTime + delta time * number of data points
  /// @param data The data to add. This also add a time stamp to the data equals
  /// to the number of data points times the delta time
  void add(const DataPoint &data) override;

protected:
  /// @brief The time frequency of the data
  DECLARE_PROTECTED_MEMBER(std::chrono::microseconds, DeltaTime);
};

} // namespace STIMWALKER_NAMESPACE::data

#endif // __STIMWALKER_DATA_FIXED_TIME_SERIES_H__